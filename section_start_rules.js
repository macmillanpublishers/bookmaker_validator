var fs = require('fs');
var cheerio = require('cheerio');


// -------------------------------------------------------    LOCAL DECLARATIONS
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


// -------------------------------------------------------   FUNCTIONS
function styleCharCleanup(style) {
  // remove spaces and paren characters, escape pound signs
  converted = style.replace(/[ ()]/g,'').replace(/#/g,'\\#');
  return converted;
}

// convert array of stylenames bookmaker classes
function toClasses(myArray) {
  var newArray = [];
  myArray.forEach(function(part, index, myArray) {
    converted = "." + styleCharCleanup(myArray[index]);
    newArray.push(converted);
  });
  return newArray;
}

// convert array of stylenames to string of bookmaker classes
function toClassesAndFlatten(myArray) {
  newArray = toClasses(myArray);
  flatArray = newArray.join(", ");
  return flatArray;
}

function makeID() {
  idCounter++;
  return "ssid" + Math.random().toString(36).substr(2, 4) + idCounter;
}

function evalMultiple(rule, ssClassName) {
  if (rule['multiple'] == false) {
    if($("." + ssClassName).length > 0) {
      console.log(ssClassName + " already exists in the html, we will not insert again")
      return false
    } else {
      // this ss is not already present in the html
      return true
    }
  } else {
    // multiples are allowed
    return true
  }
}

function evalOptionalHeaders(rule, match) {
  // get our optional_headings class list ready
  var optionalHeadingStyleList = toClassesAndFlatten(rule['optional_heading_styles']);
  // set matching para and leading para vars
  var matchingPara = match;
  var leadingPara = match.prev();
  // adjust for optional headers
  while (leadingPara.is(optionalHeadingStyleList)) {
    console.log("optional header encountered: " + leadingPara.attr('class'));
    var matchingPara = leadingPara;
    var leadingPara = leadingPara.prev();
  }
  return [matchingPara, leadingPara];
}

function evalFirstChild(rule, matchingPara) {
  if (rule['first_child'] == true) {
    // check if we have a positive match
    var matchFound = false;
    rule['first_child_text'].forEach(function (firstChildString) {
      if (matchingPara.text().toLowerCase().includes(firstChildString.toLowerCase())) {
        matchFound = true;
      }
    })
    // return values based on matchFound & desired match (positive or negative)
    if (rule['first_child_match'] == true && matchFound == true) {
      console.log("found 1st child positive match: " + matchingPara.text());
      return true;
    } else if (rule['first_child_match'] == false && matchFound == false) {
      console.log("found 1st child negative match: " + matchingPara.text());
      return true;
    } else {
      console.log("1st child match criteria not met: " + matchingPara.text());
      return false;
    }
   } else {
    console.log("no 1st child criteria for " + rule['rule_name']);
    return true;
   }
}

function evalPosition(rule, match, section_types) {
  if (rule['position']) {
    // setting a default val for conditionals below
    var position = false;

    // get our Class lists by section ready
    var fmStyleList = toClassesAndFlatten(section_types['frontmatter_sections']);
    var mainStyleList = toClassesAndFlatten(section_types['main_sections']);
    var bmStyleList = toClassesAndFlatten(section_types['backmatter_sections']);

    // see if our matched para is in the desired section
    if (rule['position'] == 'frontmatter') {
      if (match.prevAll(mainStyleList).length == 0) {
        var position = true;
      }
    } else if (rule['position'] == 'main') {
      if (match.nextAll(fmStyleList).length == 0 && match.nextAll(bmStyleList).length == 0) {
        var position = true;
      }
    } else if (rule['position'] == 'backmatter') {
      if (match.nextAll(mainStyleList).length == 0) {
        var position = true;
      }
    }
    // prepare our return value
    if (position == true) {
      console.log("'position' criteria " + rule['position'] + " matched!");
      return true;
    } else {
      console.log("'position' criteria " + rule['position'] + " NOT matched.");
      return false;
    }
  } else {
    console.log("no 'position' criteria for " + rule['rule_name']);
    return true;
  }
}

function evalPreviousSibling(rule, leadingPara) {
    var styleList = toClassesAndFlatten(rule['styles']);
    var requiredStyleList = toClassesAndFlatten(rule['required_styles']);

    if (leadingPara.is(requiredStyleList+", "+styleList)) {
      console.log("Previous sibling is already a required style");
      return false;
    } else {
      console.log("Previous sibling is not a required style!");
      return true;
    }
}

function evalPreviousUntil(rule, matchingPara) {
  if (rule['previous_until'].length > 0) {
    // get our style items converted to classes and flatten array
    var requiredStyleClasses = toClasses(rule['required_styles']);
    var requiredStyleList = toClassesAndFlatten(rule['required_styles']);
    var previousUntilList = toClassesAndFlatten(rule['previous_until']);

    // get all matches to prevUntilStop or requiredStyles
    var prevAllMatches = matchingPara.prevAll(requiredStyleList + ", " + previousUntilList);
    // make sure we matched something..
    if (prevAllMatches.length > 0) {
      // get an array of classes present on FIRST prev match
      prevMatchedClass = prevAllMatches.attr('class').split(" ");
      // see if 1st matched previous element had a required style (have to check each class of element)
      var prevUntilMatch = true;
      prevMatchedClass.forEach(function (matchedClass) {
        if (requiredStyleClasses.includes("." + matchedClass)) {
          prevUntilMatch = false;
        }
      })
      if (prevUntilMatch == true) {
        console.log("A prevUntil class was found before a required one: " + prevMatchedClass);
        return true;
      } else if (prevUntilMatch == false) {
        console.log("A required Class was found before a prevUntil one, we will not insert an SS : " + prevMatchedClass);
        return false;
      }
    } else {
      console.log("Neither prevUntil nor required Style found, ready to insert SectionStart");
      return true;
    }
  } else {
    console.log("previous_until is not a criteria for " + rule['rule_name']);
    return true;
  }
}

function evalSectionRequired(rule, ssClassName) {
  // we only wnat to run this on the last rule for a given section-start style
  if (rule['section_required'] == true && rule['last'] == true) {
    // get our insertBefore styles converted to classes, flattened
    var insertBeforeStyleList = toClassesAndFlatten(rule['insert_before']);
    // check to see if required ss present
    if($("." + ssClassName).length == 0) {
      if ($(insertBeforeStyleList).length > 0) {
        var insertionPoint = $(insertBeforeStyleList).first();
        // define our para to be inserted
        var ssPara = $("<p/>").addClass(ssClassName).attr('id',makeID());
        // insert ss para
        insertionPoint.before(ssPara);
        console.log("required ss not found, so inserted '" + ssClassName + "' before element with class: " + insertionPoint.attr('class'));
      } else {
        console.log("required ss not found, but neither were any insertBefore classes, so I could not insert ss");
      }
    } else {
      console.log("section_required: required ss already exists somewhere in the MS, yay!");
    }
  } else {
    console.log("section_required is n/a");
  }
}

function processRule(rule, section_types) {
  // make ssName style a classname:
  var ssClassName = styleCharCleanup(rule['ss_name']);

  // get styles converted to classes and flattened
  var styleList = toClassesAndFlatten(rule['styles']);

  // select paras matching 'styles'
  var match = $(styleList);

  // cycle through each match
  match.each(function() {
    // account for optional headers
    var keyParas = evalOptionalHeaders(rule, $(this));
    var matchingPara = keyParas[0];
    var leadingPara = keyParas[1];

    // check criteria for multiple
    var multipleResults = evalMultiple(rule, ssClassName)
    // check criteria for position
    var positionResults = evalPosition(rule, matchingPara, section_types);
    // check criteria for first child
    var firstChildResults = evalFirstChild(rule, matchingPara);
    // check criteria for previous sibling
    var previousSiblingResults = evalPreviousSibling(rule, leadingPara);
    // check criteria for previous until
    var previousUntilResults = evalPreviousUntil(rule, matchingPara);

    if (multipleResults == true) {
      if (previousSiblingResults == true) {
        if (firstChildResults == true) {
          if (positionResults == true) {
            if (previousUntilResults == true) {
              // define our para to be inserted
              var ssPara = $("<p/>").addClass(ssClassName).attr('id',makeID());
              // insert section style
              matchingPara.before(ssPara);
              console.log("adding SS – leading para class: '" + leadingPara.attr('class') + "' matching para class: '" + matchingPara.attr('class') + "'");

              // 'return false' breaks the 'each' loop for when we only want the first possible match:
              if (rule['multiple'] == false) {
                console.log("not checking any more matches, 'multiple' is set to false")
                return false;
              }
            }
          }
        }
      }
    }
  });

  // apply section required rule if applicable
  evalSectionRequired(rule, ssClassName);
}


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
