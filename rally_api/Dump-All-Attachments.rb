#!/usr/bin/env ruby

# ------------------------------------------------------------------------------
# SCRIPT:
#	Dump-All-Attachments.rb
#
# PURPOSE:
#	Used to dump all the attachments of a Rally subscription into individual
#	files for archival.
#
# USAGE:
#	1) Change these three variables below to match your login:
#		- $my_base_url
#		- $my_username
#		- $my_password
#
#	2) Invoke the script:
#		./Dump-All-Attachments.rb
#
#	3) All attachments found will be saved in:
#		- ./Saved_Attachments/WS####/FmtIDs/attachment-###.<type>.<ext>
#	   Where:
#		WS### - is the ordinal workspace number found (1 based).
#		FmtIDs - is the combination of the FormattedID(s) of the Artifact,
#			TestCaseResult or TestSet to which the attachment
#			belongs.
#		attachment-### - is the ordinal attachment number found in a
#			given workspace (1 based).
#		<type> - is the type of file, either "METADATA" or "DATA".
#		<ext> - is the file extension found on the attachment. Used on
#			the DATA <type> file only.
#
# API DOCS:
#       http://dev.developer.rallydev.com/developer/ruby-toolkit-rally-rest-api-json
#       https://github.com/RallyTools/RallyRestToolkitForRuby
#
# RUBY REQUIREMENTS:
#	Tested on Ruby Versions:
#		ruby-1.9.3-p194
#		ruby-1.9.3-p327
#	Required Gems:
#		rally_api (0.8.4)
#		httpclient (2.3.2) -- Usually included with the rally_api gem
#
# ------------------------------------------------------------------------------


$my_base_url	= "https://rally1.rallydev.com/slm"
$my_username	= "username@company.com"
$my_password	= "ChienChien"
$my_vars	= "./my_vars3.rb"

if FileTest.exist?( $my_vars ); puts "Loading variables from <#{$my_vars}>..."; require $my_vars; end

require "rally_api"
require "base64"
require "pp"


# ------------------------------------------------------------------------------
# Check for proper args.
#
def fixup_args ()

  print "Using Ruby version: #{RUBY_VERSION}-p#{RUBY_PATCHLEVEL}\n"

  if $my_base_url[-4..-1] != "/slm" && $my_base_url[-5..-1] != "/slm/"
    print "Fixup: Modifing URL from <#{$my_base_url}>"
    if $my_base_url[-1..-1] == "/"
      $my_base_url.concat("slm")
    else
      $my_base_url.concat("/slm")
    end
    print " to <#{$my_base_url}>\n"
  end
end


# ------------------------------------------------------------------------------
# Connect to Rally.
#
def connect_to_Rally ()
  custom_headers		= RallyAPI::CustomHttpHeader.new()
  custom_headers.name	= "Dump-All-Attachments"
  custom_headers.vendor   = "JP code"
  custom_headers.version  = "3.14"

  config	= {	:base_url	=> $my_base_url,
               :username	=> $my_username,
               :password	=> $my_password,
               :workspace	=> nil,
               :project	=> nil,
               :version	=> $my_api_version,
               :headers	=> custom_headers}

  print "Attempting connection to Rally as username #{config[:username]} at URL <#{$my_base_url}>...\n"
  @rallycon = RallyAPI::RallyRestJson.new(config)
  print "Connection to Rally succeeded.\n"
end


# ------------------------------------------------------------------------------
# Query for Subscription information.
#
def get_subscription_data ()

  # https://github.com/RallyTools/RallyRestToolkitForRuby/blob/master/lib/rally_api/rally_query.rb
  # Query options:	Example:			Default if nil:
  # --------------------	------------------------------	----------------------------------------
  # .type			:Defect, :Story, etc		---
  # .query_string		"(State = \"Closed\")"		---
  # .fetch		"Name,State,etc"		---
  # .workspace		workspace json object or ref	workspace passed in RallyRestJson.new
  # .project		project   json object or ref	project   passed in RallyRestJson.new
  # .project_scope_up	true, false			false
  # .project_scope_down	true, false			false
  # .order		"ObjectID asc"			---
  # .page_size		50, 100				200
  # .limit		1000, 2000			99999
  # --------------------	------------------------------	----------------------------------------

  query		= RallyAPI::RallyQuery.new()
  query.type	= :subscription
  query.fetch	= "Name,Workspaces,State,Projects"

  print "Attempting query for <#{query.type}> objects...\n"
  my_subs		= @rallycon.find(query)
  @rallysub	= my_subs.first
  print "Query for <#{query.type}> objects returned a total of <#{my_subs.total_result_count}>; Using first; Name=<#{@rallysub.Name}>\n"
end


# ------------------------------------------------------------------------------
# Get all Workspaces in the Subscription (sorted).
#
def get_all_workspaces ()
  @all_workspaces = @rallysub.Workspaces
  print "Subscription contains <#{@all_workspaces.count}> Workspaces.\n"
  @all_workspaces.sort {|v1,v2| v1.Name <=> v2.Name}
end


# ------------------------------------------------------------------------------
# Create a directory (with caveats).
               #
DIR_NEW=0	# Directory must be new (exit if it exists)
DIR_CANBOLD=1	# Use existing directory if it already exists

def make_my_dir (dirname, state)

  if Dir.exists?(dirname) && state == DIR_NEW
    puts "ERROR-01: Directory already exists; name=<#{dirname}>\n"
    exit
  end

  if Dir.exists?(dirname)
    return
  else
    Dir.mkdir (dirname)
    if ! Dir.exists?(dirname)
      puts "ERROR-02: Could not create directory; name=<#{dirname}>\n"
      exit
    end
  end
end


# ------------------------------------------------------------------------------
# Get a count of the number of OPEN Projects in this Workspace.
#
def get_open_project_count (this_WS)
  query			= RallyAPI::RallyQuery.new()
  query.workspace		= this_WS
  query.project		= nil
  query.project_scope_up	= true
  query.project_scope_down= true
  query.type		= :project
  query.fetch		= "Name"
  query.query_string	= "(State = \"Open\")"

  begin #{
    all_open_projects	= @rallycon.find(query)
    open_project_count	= all_open_projects.total_result_count
  rescue Exception => e
    open_project_count	= 0
  end #}

  return (open_project_count)
end


# ------------------------------------------------------------------------------
# Get all the attachments in a Workspace.
#
def get_all_WS_attachments (this_WS)
  query		= RallyAPI::RallyQuery.new()
  query.workspace	= this_WS
  query.type	= :attachment

  query.fetch	=		"Artifact"
  query.fetch	= query.fetch + ",Build"
  query.fetch	= query.fetch + ",Content"
  query.fetch	= query.fetch + ",ContentType"
  query.fetch	= query.fetch + ",CreationDate"
  query.fetch	= query.fetch + ",Date"
  query.fetch	= query.fetch + ",Description"
  query.fetch	= query.fetch + ",DisplayName"
  query.fetch	= query.fetch + ",EmailAddress"
  query.fetch	= query.fetch + ",FormattedID"
  query.fetch	= query.fetch + ",LastUpdateDate"
  query.fetch	= query.fetch + ",Name"
  query.fetch	= query.fetch + ",ObjectID"
  query.fetch	= query.fetch + ",Size"
  query.fetch	= query.fetch + ",TestCase"
  query.fetch	= query.fetch + ",TestCaseResult"
  query.fetch	= query.fetch + ",TestSet"
  query.fetch	= query.fetch + ",User"

  all_WS_atts	= @rallycon.find(query)

  return (all_WS_atts)
end


# ------------------------------------------------------------------------------
# Main code starts here.
#
fixup_args()
connect_to_Rally()
get_subscription_data()

get_all_workspaces()
total_ALL_WS = @all_workspaces.count


# ------------------------------------------------------------------------------
# Create a new directory to hold all attachments.
#
rootdir = "./Saved_Attachments"
print "Creating the root directory for saving attachments: <#{rootdir}>\n"
make_my_dir(rootdir,DIR_NEW)


# ------------------------------------------------------------------------------
# Loop through, processing each Workspace we found.
    #
cnt_ALL_att = 0
total_Bytes = 0
typeHash = Hash.new (0)

@all_workspaces.each_with_index do |this_WS, cnt_ws| #{

                                                     # Debugging code ... don't do them all
                                                     #if cnt_ws != 10531 then
                                                     #	next
                                                     #end

  print "WS[%03d of %03d] Name=<#{this_WS.Name}>  State=<#{this_WS.State}>"%[cnt_ws+1,total_ALL_WS]
  if this_WS.State == "Closed"
    print "...  being skipped.\n"
    next
  end


  # ----------------------------------------------------------------------
  # Only process Workspaces which have at least one OPEN Project.
      #
  open_project_count = get_open_project_count(this_WS)
  print "  OPENprojects=<#{open_project_count}>"
  if open_project_count < 1 #{
    print "...  being skipped.\n"
    next
  end #} of "if open_project_count < 1"


  # ----------------------------------------------------------------------
  # Get all attachments in the Workspace.
  #
  all_WS_attachments = get_all_WS_attachments(this_WS)
  print "  Attachments=<#{all_WS_attachments.total_result_count}>"
  if all_WS_attachments.total_result_count < 1 #{
    print "...  being skipped.\n"
    next
  end
  print ".\n"


  # ----------------------------------------------------------------------
  # Loop through and process each Attachment.
  #
  all_WS_attachments.each_with_index do |this_WS_att,cnt_WS_att| #{
    cnt_ALL_att = cnt_ALL_att + 1

    print "     %05d - Attachment[%03d] Size=<#{this_WS_att.Size}>\n"%[cnt_ALL_att,cnt_WS_att+1]
    # Debugging code ... don't do them all
    #if cnt_ALL_att != 35 then
    #	next
    #end


    # --------------------------------------------------------------
    # Create a new directory within our rootdir for each ordinal
    # Workspace number.
    #
    dirnameWS = rootdir + "/WS%03d/"%[cnt_ws+1]
    if cnt_WS_att == 0
      print "Create a workspace directory within the rootdir for saving attachments: <#{dirnameWS}>\n"
      make_my_dir(dirnameWS,DIR_NEW)
    end
    dirnameAR = dirnameWS


    # --------------------------------------------------------------
    # Save Artifact information (if any) from this attachment.
        #
    total_Bytes = total_Bytes + this_WS_att.Size
    if this_WS_att.Artifact != nil #{
      arFID = this_WS_att.Artifact.FormattedID
      arCRD = this_WS_att.Artifact.CreationDate
      arLUD = this_WS_att.Artifact.LastUpdateDate
      dirnameAR = dirnameAR + arFID
    else
      arFID = "(n/a)"
      arCRD = "(n/a)"
      arLUD = "(n/a)"
    end #} of "if this_WS_att.Artifact != nil"


    # --------------------------------------------------------------
    # Save TestCaseResult information (if any) from this attachment.
        #
    tsFID = "(n/a)"
    if this_WS_att.TestCaseResult != nil #{
      tcrDT = this_WS_att.TestCaseResult.Date
      tcrBL = this_WS_att.TestCaseResult.Build
      tcFID = "#{this_WS_att.TestCaseResult.TestCase.FormattedID}"
      dirnameAR = dirnameAR + tcFID

      # ------------------------------------------------------
      # Does this Attachment.TestCaseResult also have a TestSet?
      if this_WS_att.TestCaseResult.TestSet != nil
        tsFID = "#{this_WS_att.TestCaseResult.TestSet.FormattedID}"
        dirnameAR = dirnameAR + "-" + tsFID
      end
    else
      tcrDT = tcrBL = tcFID = "(n/a)"
      # ------------------------------------------------------
      # Does Attachment have neither an Artifact or a TestCaseResult?
      if arFID == "(n/a)"
        print "WARNING: Orphaned attachment found (has no Artifact or TestCaseResult).\n"
        dirnameAR = dirnameAR + "-Orphaned"
      end
    end #} of "if this_WS_att.TestCaseResult != nil"


    # --------------------------------------------------------------
    # Create a new directory within our Workspace directory for each
    # artifact or testcase or testset.
    #
    print "Create an artifact directory within the workspace directory for saving attachments: <#{dirnameAR}>\n"
    make_my_dir(dirnameAR,DIR_CANBOLD)


    # --------------------------------------------------------------
    # Create a META-data file.
    #
    fileNameMeta = dirnameAR + "/attachment-%03d.META.txt"%[cnt_WS_att+1]
    print         "           Creating METADATA; filename=<#{fileNameMeta}>\n"
    fileMeta = File.new(fileNameMeta,"w")

    fileMeta.syswrite "Attachment.Artifact.FormattedID                : #{arFID}\n"
    fileMeta.syswrite "Attachment.Artifact.CreationDate               : #{arCRD}\n"
    fileMeta.syswrite "Attachment.Artifact.LastUpdateDate             : #{arLUD}\n"
    fileMeta.syswrite "Attachment.TestCaseResult.Date                 : #{tcrDT}\n"
    fileMeta.syswrite "Attachment.TestCaseResult.Build                : #{tcrBL}\n"
    fileMeta.syswrite "Attachment.TestCaseResult.TestCase.FormattedID : #{tcFID}\n"
    fileMeta.syswrite "Attachment.TestCaseResult.TestSet.FormattedID  : #{tsFID}\n"
    fileMeta.syswrite "Attachment.ContentType                         : #{this_WS_att.ContentType}\n"
    fileMeta.syswrite "Attachment.Description                         : #{this_WS_att.Description}\n"
    fileMeta.syswrite "Attachment.Name                                : #{this_WS_att.Name}\n"
    fileMeta.syswrite "Attachment.Size                                : #{this_WS_att.Size}\n"
    fileMeta.syswrite "Attachment.User.EmailAddress                   : #{this_WS_att.User.EmailAddress}\n"
    fileMeta.syswrite "Attachment.User.DisplayName                    : #{this_WS_att.User.DisplayName}\n"

    fileMeta.close


    # --------------------------------------------------------------
    # Create a real data file which contains the decoded (from Base64)
    # Attachment content.
    #
    fileNameData = dirnameAR + "/attachment-%03d.DATA"%[cnt_WS_att+1]

    if this_WS_att.Content == nil
      # *sigh* it is possible...
      ext = ".empty"
      fileData = File.new(fileNameData+ext,"w")
    else
      ext = "." + this_WS_att.Name.split(".")[-1]
      fileData = File.new(fileNameData+ext,"w")
      this_content = this_WS_att.Content.read
      fileData.syswrite(Base64.decode64(this_content.Content))
    end
    typeHash[ext.downcase] += 1
    print         "           Wrote DATA filename=<#{fileNameData}>  Size=<#{this_WS_att.Size}>\n"

    fileData.close

  end #} of "all_WS_attachments.each_with_index do |this_WS_att,cnt_WS_att|}

end #} of "all_workspaces.each_with_index do |this_WS, cnt_ws|"

byteStr = total_Bytes.to_s.gsub(/(\d)(?=(\d\d\d)+(?!\d))/, "\\1,")
print "Found a total of <#{cnt_ALL_att}> attachments in ALL WORKSPACES; total bytes = <%s>.\n"%[byteStr]
pp typeHash.sort

#end#
