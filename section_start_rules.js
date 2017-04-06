var fs = require('fs');
var cheerio = require('cheerio');

// --------------------------------------------  LOCAL DECLARATIONS
var file = process.argv[2];

// read in json
var rulesjson = require(process.argv[3]);

// set idCounter for id gneration function
var idCounter = 0;

// Read in file contents
fs.readFile(file, function editContent (err, contents) {
  $ = cheerio.load(contents, {
          xmlMode: true
        });


// -------------------------------------------- FUNCTIONS
// convert array of stylenames to array of bookmaker classes
function stylesToClasses(myArray) {
  myArray.forEach(function(part, index, myArray) {
  myArray[index] = "." + myArray[index].replace(/[ ()]/g,'');
})};

function makeNot(list) {
  return "body:not(" + list + "), section:not(" + list + "), div:not(" + list + "), blockquote:not(" + list + "), h1:not(" + list + "), pre:not(" + list + "), aside:not(" + list + "), p:not(" + list + "), li:not(" + list + "), figure:not(" + list + ")";
}

function makeID() {
  idCounter++
  return "ssid" + Math.random().toString(36).substr(2, 4) + idCounter
}

function evalFirstChild(rule, matchingPara) {
  if (rule['first_child_match'] == 'True' && matchingPara.text() == rule['first_child_text']) {
    console.log("found 1st child positive match: " + matchingPara.text())
    return true
  } else if (rule['first_child_match'] == 'False' && matchingPara.text() != rule['first_child_text']) {
    console.log("found 1st child negative match: " + matchingPara.text())
    return true
  } else {
    console.log("1st child match criteria not met: " + matchingPara.text())
    return false
  }
}

function evalPosition(rule, match, section_types) {
  if rule['position'] == 'frontmatter' {
    if 
  } else if rule['position'] == 'main' {

  } else if rule['position'] == 'backmatter' {

  } else {
    return false
  }
}

function processRule(rule, section_types) {
  // Are our values getting here?
  // console.log("rule_name : " + rule['rule_name']);
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
  // console.log("previous_sibling : " + rule['previous_sibling']);
  // console.log("previous_until : " + rule['previous_until']);
  // console.log("required_styles : " + rule['required_styles']);
  // console.log("previous_until_stop : " + rule['previous_until_stop']);
  // console.log("last : " + rule['last']);
  // console.log(section_types['frontmatter_sections']);
  // console.log(file);

//   // Get to work!:

// convert array of stylenames to array of classes
var ssName = rule['ss_name'].replace(/[ ()]/g,'');

stylesToClasses(rule['styles'])
stylesToClasses(rule['required_styles'])
stylesToClasses(rule['optional_heading_styles'])
stylesToClasses(rule['previous_until_stop'])

var styleList = rule['styles'].join(", ");
// var notStyleList = makeNot(styleList);
var requiredStyleList = rule['required_styles'].join(", ");
var optionalHeadingStyleList = rule['optional_heading_styles'].join(", ");
var previousUntilStopList = rule['previous_until_stop'].join(", ");
  
var position = false  // default value for position check
var required_style_present = false  // default value for previous_until check
var firstChildFound = false // default value for first child check

var match = $(styleList)
// if we are not matching multiples, select first only
if (rule['multiple'] == 'False') {
  var match = $(styleList).first()
}
if (optionalHeadingStyleList) {
  console.log("optionals detected: ")
}

// new work with first children
match.each(function() {
  var matchingPara = $(this)
  var leadingPara = $(this).prev()

  if (rule['position']) {
    console.log("position is indicated!")
    position = evalPosition(rule['position'], $(this), section_types)
  }

  // account for optional headers
  while (leadingPara.is(optionalHeadingStyleList)) {
    console.log("optional header encountered: " + leadingPara.attr('class'))
    var matchingPara = leadingPara
    var leadingPara = leadingPara.prev()
  }
  // go check first child criteria in evalFirstChild function
  if (rule['first_child'] == 'True') {
    firstChildFound = evalFirstChild(rule, matchingPara)
    console.log("fcf is " + firstChildFound)
  }
  // define our para for insertion
  var ssPara = $("<p/>").addClass(ssName).attr('id',makeID());

  if (rule['previous_sibling'] == 'True') {
    // check criteria for previous_sibling
    if (!leadingPara.is(requiredStyleList+", "+styleList)) {
      // check criteria for first child
      if (rule['first_child'] == 'True' && firstChildFound == true) {
        // check criteria for position
        if (rule['position'] && position == true)
          // Insert section style
          console.log("adding SS - leading para class was: " + leadingPara.attr('class'))
          matchingPara.before(ssPara)
        }  
      } 
    }
  } else if (rule['previous_until'] == 'True') {

    // get all matches to prevUntilStop or requiredStyles
    var prevAllMatches = matchingPara.prevAll(requiredStyleList + ", " +previousUntilStopList)
    // get an array of classes present on FIRST prev match
    prevMatchedClass = prevAllMatches.attr('class').split(" ")
    // see if 1st matched previous element had a required style
    prevMatchedClass.forEach(function (matchedClass) {
      if (requiredStyleList.includes("." + matchedClass)) {
        console.log(matchedClass)
        required_style_present = true
      }
    })
    // check criteria for previous until:
    if (required_style_present == false) {
      // check criteria for first child
      if (rule['first_child'] == 'True' && firstChildFound == true) {
        //check criteria for position
        if (rule['position'] && position == true)
          // Insert section style
          console.log("adding SS - prevUntil para class was: " + prevMatchedClass)
          matchingPara.before(ssPara)
        }  
      } 
    }
}});







// }

}

// Constructor for section start rules
function Rule(key, values_hash, rule_number, section_types) {
  if (rule_number < 9) {
    criteria_count = '0' + rule_number;
  } else {
    criteria_count = rule_number;
  }

  this.rule_name = key + "_" + criteria_count;
  this.ss_name = key;
  if (values_hash.hasOwnProperty('section_required')) {
    this.section_required = 'True';
    this.insert_before = values_hash['section_required']['insert_before'];
  } else {
    this.section_required = 'False';
    this.insert_before = [];
  }
  this.multiple = values_hash["contiguous_block_criteria_" + criteria_count]['multiple'];
  this.styles = values_hash["contiguous_block_criteria_" + criteria_count]['styles'];
  if (values_hash["contiguous_block_criteria_" + criteria_count].hasOwnProperty('position')) {
    this.position = values_hash["contiguous_block_criteria_" + criteria_count]['position'];
  } else {
    this.position = '';
  }
  if (values_hash["contiguous_block_criteria_" + criteria_count].hasOwnProperty('optional_heading_styles')) {
    this.optional_heading_styles = values_hash["contiguous_block_criteria_" + criteria_count]['optional_heading_styles'];
  } else {
    this.optional_heading_styles = [];
  }
  if (values_hash["contiguous_block_criteria_" + criteria_count].hasOwnProperty('first_child')) {
    this.first_child = 'True';
    this.first_child_text = values_hash["contiguous_block_criteria_" + criteria_count]['first_child']['text'];
    this.first_child_match = values_hash["contiguous_block_criteria_" + criteria_count]['first_child']['match'];
  } else {
    this.first_child = 'False';
    this.first_child_text = [];
    this.first_child_match = '';
  }
  if (values_hash["contiguous_block_criteria_" + criteria_count].hasOwnProperty('previous_sibling')) {
    this.previous_sibling = 'True';
    this.previous_until = 'False';
    this.required_styles = values_hash["contiguous_block_criteria_" + criteria_count]['previous_sibling']['required_styles'];
    this.previous_until_stop = [];
  } else {
    this.previous_sibling = 'False';
    this.previous_until = 'True';
    this.required_styles = values_hash["contiguous_block_criteria_" + criteria_count]['previous_until']['required_styles'];
    this.previous_until_stop = values_hash["contiguous_block_criteria_" + criteria_count]['previous_until']['previous_until_stop'];
  }
  // 'last' is to let processRule know if there are more rules coming for this SS; important when 'section_required' = true
  next_rule = rule_number + 1;
  if (values_hash.hasOwnProperty("contiguous_block_criteria_" + next_rule) || values_hash.hasOwnProperty("contiguous_block_criteria_0" + next_rule)) {
    this.last = 'False'
  } else {
    this.last = 'True'
  }

  processRule(this, section_types);

  // if there is a successive contiguous_block_criteria, make a new rule and process it!
  if (this.last == 'False') {
    var obj = new Rule(key, values_hash, next_rule, section_types);
  }
}

// -------------------------------------------  RUN
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

// Run through Section Starts WITHOUT section_required, apply rules
for(ss in rulesjson) {
  if (!rulesjson[ss].hasOwnProperty('section_required')) {
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
