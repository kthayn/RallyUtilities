require 'rubygems'
require 'rally_rest_api'
require 'time'

rally_id = "user@company.com"
rally_pw = "password"


#connecting to Rally
rally_url = "https://rally1.rallydev.com/slm"
rally = RallyRestAPI.new(:base_url => rally_url, :username => rally_id, :password => rally_pw, :version => "1.34")

#test case fields
fields = {
    :name => "Take that + plus",
    :method => "Manual",
    :priority => "Critical"
}

#create test case
rally.create(:test_case, fields)
