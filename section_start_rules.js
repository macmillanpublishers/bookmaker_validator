var fs = require('fs');
var cheerio = require('cheerio');


// -------------------------------------------------------    LOCAL DECLARATIONS
var file = process.argv[2];

// read in section-start_rules.json
var rulesjson = require(process.argv[3]);

// read in style_config.json
var styleconfig = require(process.argv[4]);

// set versatileBlockParas var
var versatileBlockParas = styleconfig['versatileblockparas'].join(", ")

// set idCounter for id gneration function
var idCounter = 0;

// Read in file contents
fs.readFile(file, function editContent (err, contents) {
  $ = cheerio.load(contents, {
          xmlMode: true
        });


// -------------------------------------------------------   FUNCTIONS
  // remove spaces and paren characters, escape pound signs from stylenames
function styleCharCleanup(style) {
  converted = style.replace(/[ ()]/g,'').replace(/#/g,'\\#');
  return converted;
}

// convert array of stylenames to an array of bookmaker classes
function toClasses(myArray) {
  var newArray = [];
  myArray.forEach(function(part, index, myArray) {
    converted = "." + styleCharCleanup(myArray[index]);
    newArray.push(converted);
  });
  return newArray;
}

// convert array of stylenames to a string of bookmaker classes
function toClassesAndFlatten(myArray) {
  newArray = toClasses(myArray);
  flatArray = newArray.join(", ");
  return flatArray;
}

// make a randomm id for section starts;
// the idCounter is to make absolutely sure they're unique
function makeID() {
  idCounter++;
  return "ssid" + Math.random().toString(36).substr(2, 4) + idCounter;
}

// returns value 'false' if item with ssClass already exists & if 'multiple' is set to 'false'
//  else returns true
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

// scan upwards to reset the value of 'matchingPara' and its 'leadingPara':
//  a style from contiguous block Style list or optional header list
//  not preceded by optional headers, versatile block paras or style from Style list
// Also return whether the matching para was preceded by another mathicn style in the same block
function checkFirstStyleofBlock(rule, match) {
  // get our optional_headings and style class lists ready
  var styleList = toClassesAndFlatten(rule['styles']);
  var optionalHeadingStyleList = toClassesAndFlatten(rule['optional_heading_styles']);

  // setting selector contents for below loop(s), depending on presence of optional headers
  if (optionalHeadingStyleList) {
    var optHeadingsVersatileBlocksAndStyles = optionalHeadingStyleList + ", " + versatileBlockParas + ", " + styleList;
    var optHeadingsAndStyles = optionalHeadingStyleList + ", " + styleList;
  } else {
    var optHeadingsVersatileBlocksAndStyles = versatileBlockParas + ", " + styleList;
    var optHeadingsAndStyles = styleList;
  }

  // set matching para and leading para vars
  var matchingPara = match;
  var leadingPara = match.prev();
  var matchParaTmp = match;
  var leadParaTmp = leadingPara;
  var firstStyleOfBlock = true;

  // scan upwards through any optional headers, versatile block paras, or styles in Style list (for contiguous block criteria)
  while (leadParaTmp.is(optHeadingsVersatileBlocksAndStyles)) {
    console.log("leading optional header or versatile block para: " + leadParaTmp.attr('class'));
    // increment the loop upwards
    var matchParaTmp = leadParaTmp;
    var leadParaTmp = leadParaTmp.prev();
    // adjust matching & leadingParas if we found optional header or para with style from
    //  Style list directly preceding a versatile block para
    if (matchParaTmp.is(optHeadingsAndStyles)) {
      var matchingPara = matchParaTmp;
      var leadingPara = leadParaTmp;
      if (matchParaTmp.is(styleList)) {
        firstStyleOfBlock = false;
      }
    }
  }
  return [matchingPara, leadingPara, firstStyleOfBlock];
}

// if first-child criteria is present and met, or there is no first-child criteria, returns true
//  else returns false
function evalFirstChild(rule, matchingPara) {
  if (rule['first_child'] == true) {
    // check if we have a positive match
    var matchFound = false;
    rule['first_child_text'].forEach(function (firstChildString) {
      if (matchingPara.text().toLowerCase().indexOf(firstChildString.toLowerCase()) > -1) {
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

// if position criteria is present and met, or there is no position criteria, returns true;
//  else returns false
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

// returns false if the previous sibling is any section-start style or anything from 'required-style' list,
// Else returns true
function evalPreviousSibling(rule, leadingPara, section_types) {
    var requiredStyleList = toClassesAndFlatten(rule['required_styles']);
    var fullSectionStartList = toClassesAndFlatten(section_types['all_sections']);

    if (leadingPara.is(requiredStyleList + ", " + fullSectionStartList)) {
      console.log("Previous sibling is already a required style (or Section Start style)");
      return false;
    } else {
      console.log("Previous sibling is not a required style!");
      return true;
    }
}

// returns true if previous_until criteria is present and met, otherwise returns false
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
        if (requiredStyleClasses.indexOf("." + matchedClass) > -1) {
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

// if a rule has section_required criteria and the section-start is not present,
//  it is inserted before the first item on the 'insert_before' list that is found in the MS
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

// ----------------------- Process Section Start rules
// Here's where we walk through and apply criteria of each rule to see if we're inserting
//  a new para with Section-Start style
function processRule(rule, section_types) {
  // make section-start stylename a classname:
  var ssClassName = styleCharCleanup(rule['ss_name']);

  // get stylelist array converted to classes and flattened to string
  var styleList = toClassesAndFlatten(rule['styles']);

  // select paras matching 'styles'
  var match = $(styleList);

  // cycle through each matching para to test against rule criteria
  match.each(function() {
    // account for optional headers and versatile block paras: find the beginning of the Style block
    var keyParas = checkFirstStyleofBlock(rule, $(this));
    var matchingPara = keyParas[0];
    var leadingPara = keyParas[1];
    // boolean for whether this match was found to be the first matching style in its block
    var firstStyleOfBlock = keyParas[2];

    // if this match was preceded by other contiguous block styles within the block,
    //  move to the next match:
    if (firstStyleOfBlock == false) {
      console.log("this match is not the beginning of the contiguous block, skipping");
      return;
    }

    // Each of the following function calls evaluates matchingPara for this sectionstart-Rule
    // For all of these tests: if no value for that function is present for this rule,
    //  &/or criteria IS present for this rule AND criteria is met, it will return a value of true
    //  If criteria is specified for this rule and is NOT met, we will get a value of false:

    // check criteria for multiple
    var multipleResults = evalMultiple(rule, ssClassName)
    // check criteria for position
    var positionResults = evalPosition(rule, matchingPara, section_types);
    // check criteria for first child
    var firstChildResults = evalFirstChild(rule, matchingPara);
    // check criteria for previous sibling
    var previousSiblingResults = evalPreviousSibling(rule, leadingPara, section_types);
    // check criteria for previous until
    var previousUntilResults = evalPreviousUntil(rule, matchingPara);

    // Now any values of false from above functions will cause us to exit our nested ifs and
    //  skip ahead to check the next matched Para
    if (multipleResults == true) {
      if (previousSiblingResults == true) {
        if (firstChildResults == true) {
          if (positionResults == true) {
            if (previousUntilResults == true) {
              // All criteria were met for this rule, we need to insert a Section Start paragraph!
              // define our para to be inserted
              var ssPara = $("<p/>").addClass(ssClassName).attr('id',makeID());
              // insert section style para:
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

  // apply section_required rule if applicable
  evalSectionRequired(rule, ssClassName);
}


// ----------------------- Constructor for section start rules
// Here's where we create a Rule object for each Section-Start criteria
// Basically flattening key:values from the JSON
//  and creating empty values for the Rule object where keys are not present in the JSON
function Rule(key, values_hash, rule_number, section_types) {
  // skip any Section Start entries without criteria
  if (values_hash.hasOwnProperty('contiguous_block_criteria_01') || rule_number > 1) {
    // get a rule count as string
    if (rule_number < 9) {
      criteria_count = '0' + rule_number;
    } else {
      criteria_count = rule_number;
    }

    ////// Set values for Rule object
    // 'ss_name' is the SectionStart Name
    this.ss_name = key;
    // 'rule_name' is the SectionStart Name with a 2 digit criteria_count appended (e.g. 01, 02, etc)
    this.rule_name = key + "_" + criteria_count;
    // 'section_required' & 'insert_before' values are straight from the JSON – a boolean, and an array of styles, respectively:
    //  or 'false', & empty array if they're not present
    if (values_hash.hasOwnProperty('section_required')) {
      this.section_required = values_hash['section_required']['value']
      this.insert_before = values_hash['section_required']['insert_before'];
    } else {
      this.section_required = false;
      this.insert_before = [];
    }
    // 'position' value is the position string from the JSON, or empty string if not present in JSON
    if (values_hash.hasOwnProperty('position')) {
      this.position = values_hash['position'];
    } else {
      this.position = '';
    }
    // 'multiple' value, always present in JSON, t/f
    this.multiple = values_hash["contiguous_block_criteria_" + criteria_count]['multiple'];
    // 'styles' value, always present in JSON, an array of stylenames
    this.styles = values_hash["contiguous_block_criteria_" + criteria_count]['styles'];

    ////// The rest of the values below are nested in the "contiguous_block_criteria_xx" hash in the JSON.
    //////  Because each criteria is a separate rule, we use the rulenum/criteria_count to make sure we are
    //////  accessing values form the right 'contiguous_block_criteria'

    // 'optional_heading_styles', where present, is an array of stylenames; set to an empty array otherwise
    if (values_hash["contiguous_block_criteria_" + criteria_count].hasOwnProperty('optional_heading_styles')) {
      this.optional_heading_styles = values_hash["contiguous_block_criteria_" + criteria_count]['optional_heading_styles'];
    } else {
      this.optional_heading_styles = [];
    }
    // first_child is a boolean, true if present, false if not
    // first_child_text is an array of text values (nested under first_child), or
    //  an empty array if not present in the JSON
    // first_child_match is a boolean nested under first_child, indicating whether the desired match is positive or negative
    if (values_hash["contiguous_block_criteria_" + criteria_count].hasOwnProperty('first_child')) {
      this.first_child = true;
      this.first_child_text = values_hash["contiguous_block_criteria_" + criteria_count]['first_child']['text'];
      this.first_child_match = values_hash["contiguous_block_criteria_" + criteria_count]['first_child']['match'];
    } else {
      this.first_child = false;
      this.first_child_text = [];
      this.first_child_match = '';
    }
    // 'required_styles' value, nested under 'previous_sibling', is present in JSON for every criteria, as an array of stylenames
    this.required_styles = values_hash["contiguous_block_criteria_" + criteria_count]['previous_sibling']['required_styles'];
    // 'previous_until' value, where present, is an array of stylenames, otherwise set to empty array
    if (values_hash["contiguous_block_criteria_" + criteria_count].hasOwnProperty('previous_until')) {
      this.previous_until = values_hash["contiguous_block_criteria_" + criteria_count]['previous_until']
    } else {
      this.previous_until = [];
    }

    // calculated value 'last' is to let processRule function know if there are more criteria/Rules coming
    //  for this SectionStart; this is important to know when 'section_required' = true,
    //  because we want to run section_required function AFTER all other Rules for this Section Start have been evaluated.
    var next_rule = rule_number + 1;
    if (values_hash.hasOwnProperty("contiguous_block_criteria_" + next_rule) || values_hash.hasOwnProperty("contiguous_block_criteria_0" + next_rule)) {
      this.last = false;
    } else {
      this.last = true;
    }

    // We have our Rule object! Now we send this Rule to the processRule function to be evaluated!
    processRule(this, section_types);

    // if there is a successive contiguous_block_criteria for this Section Start in the JSON,
    //  construct a new Rule for it here by calling the constructor again (with incremented rule_number)
    if (this.last == false) {
      var obj = new Rule(key, values_hash, next_rule, section_types);
    }
  }
}


// -------------------------------------------------------  RUN
// Push SectionStart names into arrays by section-type, + one array with 'all' names
// We'll need the lists of sections-by-type to evaluate Rules with 'position' requirements
// And we'll need the list of 'all' section start names when testing 'previous_sibling'
var section_types = {all_sections:[], frontmatter_sections:[], main_sections:[], backmatter_sections:[]};
for(ss in rulesjson) {
  section_types['all_sections'].push(ss);
  if (rulesjson[ss]['section_type'] == 'frontmatter') {
    section_types['frontmatter_sections'].push(ss);
  } else if (rulesjson[ss]['section_type'] == 'main') {
    section_types['main_sections'].push(ss);
  } else if (rulesjson[ss]['section_type'] == 'backmatter') {
    section_types['backmatter_sections'].push(ss);
  }
}

// Note for future dev:  in our VBA version of this script, the below loops through rules by sequential 'Priority'
//  were abstracted/encapsulated as follows:
// - As each Rule object is created in the Constructor class, a 'priority' value (integer) is
//  calculated in a function and added as a property of the Rule.
// - Then a single loop constructs Rule objects, and a subsequent While loop processes Rules in increasing 'priority'
// Something like this could be done here if we get more complicated priority requirements

// Create a hash to contain created Rule objects
var sectionStartObject = {};

// Priority 1: rules with section_required criteria need to run before all others
for(ss in rulesjson) {
  if (rulesjson[ss].hasOwnProperty('section_required')) {
    // The '1' is to start with 1st contiguous block criteria
    sectionStartObject[ss] = new Rule(ss, rulesjson[ss], 1, section_types);
  }
}
// Priority 2: Apply rules for Section Starts WITHOUT order:last or position_requirement
for(ss in rulesjson) {
  if (!rulesjson[ss].hasOwnProperty('order') && !rulesjson[ss].hasOwnProperty('position')) {
    // exclude Section Starts we've already processed
    if (!sectionStartObject.hasOwnProperty(ss)) {
      sectionStartObject[ss] = new Rule(ss, rulesjson[ss], 1, section_types);
    }
  }
}
// Priority 3: Apply rules for Section Starts with position requirement
for(ss in rulesjson) {
  if (rulesjson[ss].hasOwnProperty('position')) {
    // exclude Section Starts we've already processed
    if (!sectionStartObject.hasOwnProperty(ss)) {
      sectionStartObject[ss] = new Rule(ss, rulesjson[ss], 1, section_types);
    }
  }
}
// Priority 4: Apply rules for Section Starts with order:last
for(ss in rulesjson) {
  if (rulesjson[ss]['order'] == 'last') {
    // exclude Section Starts we've already processed
    if (!sectionStartObject.hasOwnProperty(ss)) {
      sectionStartObject[ss] = new Rule(ss, rulesjson[ss], 1, section_types);
    }
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
