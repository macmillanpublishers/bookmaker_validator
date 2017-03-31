require 'fileutils'
require 'json'

require_relative '../bookmaker/core/utilities/mcmlln-tools.rb'
require_relative './validator_tools.rb'
require_relative './val_header.rb'


# ---------------------- LOCAL DECLARATIONS
Val::Logs.log_setup()
@logger = Val::Logs.logger
Val::Logs.return_stdOutErr


# section_start_rules_js = File.join(Paths.scripts_dir, "section_start_rules.js")
section_start_rules_js = File.join(File.dirname(__FILE__), "section_start_rules.js")
pretend_html_output = File.join(File.dirname(__FILE__), 'bookmakertestMS_pretty_orig.html')


## -------------------######### could wrap the node run in a separatemethod! : ) Stopre rules_js in the header?


class SectionStartRule
  # section_start_rules_js = File.join(Paths.scripts_dir, "section_start_rules.js")
  @@section_start_rules_js = File.join(File.dirname(__FILE__), "section_start_rules.js")
  @@pretend_html_output = File.join(File.dirname(__FILE__), 'bookmakertestMS_pretty_orig.html')
  # ## wrapping Bkmkr::Tools.runnode in a new method for this script
  # def localRunNode(jsfile, args) # status_hash)
  #   	Bkmkr::Tools.runnode(jsfile, args)
  # rescue => e
  #   p e
  #   @logger.info {"error occurred while running #{__method__.to_s}/#{jsfile}: #{e}"}
  # end

  # @@section_type_hash = {}
  # @@section_type_hash['frontmatter']=[]
  # @@section_type_hash['main']=[]
  # @@section_type_hash['backmatter']=[]

  def initialize(key, values_hash, rule_number, section_type_hash)
    #see if we're running
    # add a zero to the rule_number if its less
    criteria_count = rule_number.to_i > 9 ? rule_number.to_s : "0#{rule_number}"
    @name = "#{key}_#{criteria_count}"
    # @section_type = values_hash['section_type']
    # unless values_hash['section_required'].nil?
    if values_hash.key?('section_required')
      @section_required = 'True'
      @insert_before = values_hash['section_required']['insert_before']
    else
      @section_required = 'False'
      @insert_before = []
    end
    @multiple = values_hash["contiguous_block_criteria_#{criteria_count}"]['multiple']
    @styles = values_hash["contiguous_block_criteria_#{criteria_count}"]['styles']
    # conditional to avoid passing nil values
    # @position = values_hash["contiguous_block_criteria_#{criteria_count}"]['position'].nil? ? '' : values_hash["contiguous_block_criteria_#{criteria_count}"]['position']
    @position = values_hash["contiguous_block_criteria_#{criteria_count}"].key?('position') ? values_hash["contiguous_block_criteria_#{criteria_count}"]['position'] : ''
    # conditional to avoid passing nil values
    # @optional_heading_styles = values_hash["contiguous_block_criteria_#{criteria_count}"]['optional_heading_styles'].nil? ? [] : values_hash["contiguous_block_criteria_#{criteria_count}"]['optional_heading_styles']
    @optional_heading_styles = values_hash["contiguous_block_criteria_#{criteria_count}"].key?('optional_heading_styles') ? values_hash["contiguous_block_criteria_#{criteria_count}"]['optional_heading_styles'] : ['']
    if values_hash["contiguous_block_criteria_#{criteria_count}"].key?('first_child')
      @first_child = 'True'
      @first_child_text = values_hash["contiguous_block_criteria_#{criteria_count}"]['first_child']['text']
      @first_child_match = values_hash["contiguous_block_criteria_#{criteria_count}"]['first_child']['match']
    else
      @first_child = 'False'
      @first_child_text = []
      @first_child_match = ''
    end
    if values_hash["contiguous_block_criteria_#{criteria_count}"].key?('previous_sibling')
      @previous_sibling = 'True'
      @previous_until = 'False'
      @required_styles = values_hash["contiguous_block_criteria_#{criteria_count}"]['previous_sibling']['required_styles']
      @previous_until_stop = []
    else
      @previous_sibling = 'False'
      @previous_until = 'True'
      @required_styles = values_hash["contiguous_block_criteria_#{criteria_count}"]['previous_until']['required_styles']
      @previous_until_stop = values_hash["contiguous_block_criteria_#{criteria_count}"]['previous_until']['previous_until_stop']
    end

    # #set up our arrays for sections by location-label
    # if @section_type == 'frontmatter'
    #   @@section_type_hash['frontmatter'].push(key)
    # elsif @section_type == 'main'
    #   @@section_type_hash['main'].push(key)
    # elsif @section_type == 'backmatter'
    #   @@section_type_hash['backmatter'].push(key)
    # end

    # Rebuild hash:
    @@thisSectionStart = {
      'name' => @name,
      'section_required' => @section_required,
      'insert_before' => @insert_before,
      'multiple' => @multiple,
      'styles' => @styles,
      'position' => @position,
      'optional_heading_styles' => @optional_heading_styles,
      'first_child' => @first_child,
      'first_child_text' => @first_child_text,
      'first_child_match' => @first_child_match,
      'previous_sibling' => @previous_sibling,
      'previous_until' => @previous_until,
      'required_styles' => @required_styles,
      'previous_until_stop' => @previous_until_stop
    }

    # send rule to be enforced!
    # Bkmkr::Tools.runnode(section_start_rules_js, "#{Val::Files.html_output} #{@@thisSectionStart} #{section_type_hash}")
    # Bkmkr::Tools.runnode(@@section_start_rules_js, "#{@@pretend_html_output} #{@@thisSectionStart} #{section_type_hash}")
    # node_output = Bkmkr::Tools.runnode(@@section_start_rules_js, "#{@@pretend_html_output} #{@@thisSectionStart} #{section_type_hash}")
    # puts node_output
    # Bkmkr::Tools.runnode(@@section_start_rules_js, "#{@@pretend_html_output}", "dogs", "cats")
    # fpath = '/Users/matthew.retzer/bookmaker-dev/bookmaker_validator/section_start_rules.js'

# puts @@section_start_rules_js, @@pretend_html_output
    # node_out = `node #{@@section_start_rules_js} #{Val::Files.ss_rules_json_test}` #{section_type_hash}`
    # puts node_out
    # `node`
    # if we have another contiguous_block_criteria, spin off a new rule object!
    next_rule = criteria_count.split('_').last.to_i + 1
    if !values_hash["contiguous_block_criteria_#{next_rule}"].nil? || !values_hash["contiguous_block_criteria_0#{next_rule}"].nil?
      SectionStartRule.new(key, values_hash, "#{next_rule}", section_type_hash)
    end

    # puts "name: #{@name}"
    # # puts "section_type: #{@section_type}"
    # puts "section_required: #{@section_required}"
    # puts "insert_before: #{@insert_before}"
    # puts "multiple: #{@multiple}"
    # puts "styles: #{@styles}"
    # puts "position: #{@position}"
    # puts "optional_heading_styles: #{@optional_heading_styles}"
    # puts "first_child: #{@first_child}"
    # puts "first_child_text: #{@first_child_text}"
    # puts "first_child_match: #{@first_child_match}"
    # puts "previous_sibling: #{@previous_sibling}"
    # puts "previous_until: #{@previous_until}"
    # puts "required_styles: #{@required_styles}"
    # puts "previous_until_stop: #{@previous_until_stop}"


  end



  # def self.section_type_hash
  #   @@section_type_hash['frontmatter'].uniq!
  #   @@section_type_hash['main'].uniq!
  #   @@section_type_hash['backmatter'].uniq!
  #   @@section_type_hash
  # end

end

section_type_hash = {}
section_type_hash['frontmatter']=[]
section_type_hash['main']=[]
section_type_hash['backmatter']=[]

Val::Hashes.ss_rules_hash.each do |key, value|
  if Val::Hashes.ss_rules_hash[key]['section_type'] == 'frontmatter'
    section_type_hash['frontmatter'] << key
  elsif Val::Hashes.ss_rules_hash[key]['section_type'] == 'main'
    section_type_hash['main'] << key
  elsif Val::Hashes.ss_rules_hash[key]['section_type'] == 'backmatter'
    section_type_hash['backmatter'] << key
  end
end

# demo launch from regular file
SectionStartRule.new(Val::Hashes.ss_rules_hash.keys[0], Val::Hashes.ss_rules_hash[Val::Hashes.ss_rules_hash.keys[0]], 1, section_type_hash)

# section_start_rules = []
# Add Section Starts fromjson as objects in Rule class
# Val::Hashes.ss_rules_hash.each do |key, value|
Val::Hashes.ss_rules_hash_test.each do |key, value|
  # section_start_rules << SectionStartRule.new(key, value, 1, section_type_hash)
  SectionStartRule.new(key, value, 1, section_type_hash)
end


node_out = `node #{section_start_rules_js} #{pretend_html_output} #{Val::Files.ss_rules_json_test}` #{section_type_hash}`
puts node_out

# puts "fm", section_type_hash['frontmatter']
# puts "main", section_type_hash['main']
# puts "bm", section_type_hash['backmatter']

# puts SectionStartRule.section_type_hash


# ObjectSpace.each_object(SectionStartRule) do |obj|
#   puts "OBJECT: #{obj.name}"
#   #do what ever you want to do with that object
# end
# SectionStartRule.each do |r|
#   puts r.name
# end

# http://stackoverflow.com/questions/882070/sorting-an-array-of-objects-in-ruby-by-object-attribute
# objects.sort_by {|obj| obj.attribute}




Val::Logs.redirect_stdOutErr(File.join(Val::Logs.logfolder,Val::Logs.logfilename))


# ---------------------- METHOD
## wrapping Bkmkr::Tools.runnode in a new method for this script
# def localRunNode(jsfile, args, status_hash)
#   	Bkmkr::Tools.runnode(jsfile, args)
# rescue => e
#   p e
#   @logger.info {"error occurred while running #{__method__.to_s}/#{jsfile}: #{e}"}
# end


#--------------------- RUN

#update status file with new news!
# Vldtr::Tools.write_json(status_hash, Val::Files.status_file)
