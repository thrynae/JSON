This interprets char array as JSON and returns an object the same size and shape as the Matlab builtin. There are many other JSON parsers for Matlab, but many have only a small range of compatibility, fail for many test cases of valid (or invalid) syntax, extend the standard, or do all three at once. This was created to have a relatively compact reader that will work for normal JSON on Matlab and Octave for a wide range of releases.

This was implemented using the [ECMA JSON syntax standard](https://www.ecma-international.org/wp-content/uploads/ECMA-404_2nd_edition_december_2017.pdf").
The failing and passing cases were validated using the test cases from a JSON test suite on [GitHub](http://github.com/nst/JSONTestSuite), containing over 300 cases of possibly ambiguous syntax. Because the standard is not explicit for every situation, there are also test cases left to the interpreter.

Note that this doesn't read a JSON **file**, but only parses the result. I'm of the opinion that a JSON parser should only parse JSON, and not do other things.

Licence: CC by-nc-sa 4.0