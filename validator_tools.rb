require 'fileutils'
require 'net/smtp'
require 'json'

module Vldtr
  class Tools

	def self.write_json(hash, json)
	    finaljson = JSON.generate(hash)
	    File.open(json, 'w+:UTF-8') { |f| f.puts finaljson }
	end

	def self.update_json(newhash, currenthash, json)
    	currenthash.merge!(newhash)
    	Vldtr::Tools.write_json(currenthash,json)
	end 

  end
end  	