var fs = require('fs');
var cheerio = require('cheerio');

// -------------------------------------------------------    LOCAL DECLARATIONS
var file = process.argv[2];

// read in json
var rulesjson = require(process.argv[3]);

// Read in file contents
fs.readFile(file, function editContent (err, contents) {
  $ = cheerio.load(contents, {
          xmlMode: true
        });


// -------------------------------------------------------   FUNCTIONS
function processRule(rule, section_types) {
  // Are our values getting here?
  // console.log("\n\nrule_name : " + rule['rule_name']);
  // console.log("ss_name : " + rule['ss_name']);
  // console.log("section_required : " + rule['section_required']);
  // console.log("insert_before : " + rule['insert_before']);
  // console.log("multiple : " + rule['multiple']);
  // console.log("styles : " + rule['styles']);
  // console.log("position : " + rule['position']);
  // console.log("optional_heading_styles : " + rule['optional_heading_styles']);
  // console.log("first_child : " + rule['first_child']);
  // console.log("first_child_text : " + rule['first_child_text']);
  // console.log("first_child_match : " + rule['first_child_match']);
  // console.log("previous_until : " + rule['previous_until']);
  // console.log("required_styles : " + rule['required_styles']);
  // console.log("last : " + rule['last']);
  // console.log(section_types['frontmatter_sections']);
  // console.log(file);


}

// Constructor for section start rules
// Constructor for section start rules
function Rule(key, values_hash, rule_number, section_types) {
  // get a rule count as string
  if (rule_number < 9) {
    criteria_count = '0' + rule_number;
  } else {
    criteria_count = rule_number;
  }

  // set values for 'rule'
  this.rule_name = key + "_" + criteria_count;
  this.ss_name = key;
  if (values_hash.hasOwnProperty('section_required')) {
    this.section_required = values_hash['section_required']['value']
    this.insert_before = values_hash['section_required']['insert_before'];
  } else {
    this.section_required = false;
    this.insert_before = [];
  }
  if (values_hash.hasOwnProperty('position')) {
    this.position = values_hash['position'];
  } else {
    this.position = '';
  }
  this.multiple = values_hash["contiguous_block_criteria_" + criteria_count]['multiple'];
  this.styles = values_hash["contiguous_block_criteria_" + criteria_count]['styles'];
  if (values_hash["contiguous_block_criteria_" + criteria_count].hasOwnProperty('optional_heading_styles')) {
    this.optional_heading_styles = values_hash["contiguous_block_criteria_" + criteria_count]['optional_heading_styles'];
  } else {
    this.optional_heading_styles = [];
  }
  if (values_hash["contiguous_block_criteria_" + criteria_count].hasOwnProperty('first_child')) {
    this.first_child = true;
    this.first_child_text = values_hash["contiguous_block_criteria_" + criteria_count]['first_child']['text'];
    this.first_child_match = values_hash["contiguous_block_criteria_" + criteria_count]['first_child']['match'];
  } else {
    this.first_child = false;
    this.first_child_text = [];
    this.first_child_match = '';
  }
  this.required_styles = values_hash["contiguous_block_criteria_" + criteria_count]['previous_sibling']['required_styles'];
  if (values_hash["contiguous_block_criteria_" + criteria_count].hasOwnProperty('previous_until')) {
    this.previous_until = values_hash["contiguous_block_criteria_" + criteria_count]['previous_until']
  } else {
    this.previous_until = [];
  }

  // 'last' is to let processRule know if there are more rules coming for this SS; important when 'section_required' = true
  var next_rule = rule_number + 1;
  if (values_hash.hasOwnProperty("contiguous_block_criteria_" + next_rule) || values_hash.hasOwnProperty("contiguous_block_criteria_0" + next_rule)) {
    this.last = false;
  } else {
    this.last = true;
  }

  processRule(this, section_types);

  // if there is a successive contiguous_block_criteria, make a new rule and process it!
  if (this.last == false) {
    var obj = new Rule(key, values_hash, next_rule, section_types);
  }
}

// -------------------------------------------------------  RUN
// Sort sections into type-labels
var section_types = {frontmatter_sections:[], main_sections:[], backmatter_sections:[]};
for(ss in rulesjson) {
  if (rulesjson[ss]['section_type'] == 'frontmatter') {
    section_types['frontmatter_sections'].push(ss);
  } else if (rulesjson[ss]['section_type'] == 'main') {
    section_types['main_sections'].push(ss);
  } else if (rulesjson[ss]['section_type'] == 'backmatter') {
    section_types['backmatter_sections'].push(ss);
  }
}

// Run through Section Starts with section_required, apply rules
for(ss in rulesjson) {
  if (rulesjson[ss].hasOwnProperty('section_required')) {
    // The '1' is to start with 1st contiguous block criteria
    var obj = new Rule(ss, rulesjson[ss], 1, section_types);
  }
}

// Apply rules for Section Starts WITHOUT section_required or position_requirement
for(ss in rulesjson) {
  if (!rulesjson[ss].hasOwnProperty('section_required') && !rulesjson[ss].hasOwnProperty('position')) {
    // The '1' is to start with 1st contiguous block criteria
    var obj = new Rule(ss, rulesjson[ss], 1, section_types);
  }
}

// Apply rules for Section Starts with position requirement (without section_required)
for(ss in rulesjson) {
  if (rulesjson[ss].hasOwnProperty('position') && !rulesjson[ss].hasOwnProperty('section_required')) {
    // The '1' is to start with 1st contiguous block criteria
    var obj = new Rule(ss, rulesjson[ss], 1, section_types);
  }
}


 // Write out file contents
  var output = $.html();
    fs.writeFile(file, output, function(err) {
      if(err) {
          return console.log(err);
      }
      console.log("Content has been updated!");
  });
});
