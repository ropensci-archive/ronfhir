# R on FHIR 

[FHIR](http://hl7.org/fhir) is pronounced 'fire'. It is a healthcare data exchange format
based on a web API that is being implemented by EHR server and other health management 
systems around the world. 

The intent of this project is to make FHIR data available to R for easy analysis

## The R on FHIR package

The project extended the [RonFHIR](https://github.com/furore-fhir/RonFHIR) project 
first developed by Sander Laverman (Furore).

We enhanced the API, and tested the functionality against the server on 
[http://test.fhir.org](http://test.fhir.org)

[Pull Request](https://github.com/furore-fhir/RonFHIR/pull/1)

## Code Fragment

```
library(RonFHIR)

# connect to the server
client <- fhirClient$new("http://test.fhir.org/r3")

# just get a random patient, and print the identifier informaation
a <- client$read(location = "Patient/example", summaryType = "true")
a$identifier

# count Patients on the server with gender = male
b <- client$search("Patient", "gender=male", summaryType="count")
b$total

# now, graphql on a resource
c <- client$qraphQL(location = "Patient/example", query = "{id name{given,family}}")
print(c)

# and a graphQL based search
d <- client$qraphQL(location = NULL, query = "{PatientList(name:\"pet\"){name @first @flatten{family,given @first}}}")
print(d)

```

The output from running this:

```
a$identifier: 

[[1]]
    use                          coding             system     value      start         display
1 usual http://hl7.org/fhir/v2/0203, MR urn:oid:2.15.288.1 622883245 2001-05-06 Acme Healthcare

b$total:
[1] 1009

c:
  data.id             data.name
1 example Adam, Everyman, Jones

d <- client$qraphQL(location = NULL, query = "{PatientList(name:\"pet\"){name @first @flatten{family,given @first}}}")
d:
  PatientList
1 Chalmers, Chalmers...., Peter, Rose...

```

## Graph Examples

Some graphs generated from data accessed by the library, based on the patient list:

`patient_list <- get_patients("http://test.fhir.org/r3")`

### Where are our patients from?
![patient city chart](whereFrom.png)

### What gender do our patients identify as?
![patient gender](gender.png)

### How old are our patients?
![patient age gender](genderage.png)

## Re-organizing the data

FHIR Resources are often quite nested- like real messy operational data.
A straight import like the example above generates deeply nested data frames
that need might need quite a bit of work the reshape them to a useful 
form for data analysis. But each analysis will need a different reshaping. For 
example, in FHIR, patients have multiple names (the name they use, 
their legal name, their maiden name, etc). But most analyses don't
care about that - they just want to use the current name for reference. 
Unless, that is, the analysis is about the name types. This pattern is 
ubiquitious - while there's some very common simplifications, there's 
a very long tail. Classically, this process is called ETL (Extract, Transform, Load). 

Rather than leaving this data cleansing functionality to R (and/or writing 
some common simplifications in R), we extended [graphQL](http://graphql.org/), 
which is already used in FHIR, to provide additional data cleansing functionality 
to R consumers.

Specifically, we added 4 directives to the FHIR profile on graphQL:
* @flatten
* @first
* @singleton
* @slice

These directives can be used to flatten the data before presenting it in FHIR. This is better because 
* it's more efficient to limit and reframe the data before transmission
* doing the reformatting in graphQL means that it can be used outside R as well
* graphql is a language with considerable support and the same technique could be adopted elsewhere too

Note that not all the transformation will be able to be done in graphQL. This is a 90/10 thing.
Additional data cleansing will almost always be needed.

### Documentation from FHIR

GraphQL is a very effective language for navigating a graph and selecting subset of information from it. However 
for some uses, the physical structure of the result set is important. This is most relevant when extracting data 
for statistical analysis in languages such as [R](https://www.r-project.org/). In order to facilitate 
these kind of uses, FHIR servers should consider supporting the following directives that allow implementers to 
flatten the return graph for easier analysis

#### Flattening a node

   @flatten

This directive indicates that the field to which it is attached is not actually produced in the output graph. 
Instead, it's children will be processed and added to the output graph as specified in it's place.
Notes:
* If @flatten is used on an element with repeating cardinality, then by default, all the children will become lists
* When using @flatten, all the collated children must have the same FHIR type. The server SHALL return an error if they don't

For an example, take this Patient resource:

```
{
  "resourceType": "Patient",
  "id": "example",
  "identifier": [
    {
      "use": "usual",
      "type": {
        "coding": [
          {
            "system": "http://hl7.org/fhir/v2/0203",
            "code": "MR"
          }
        ]
      },
      "system": "urn:oid:1.2.36.146.595.217.0.1",
      "value": "12345",
      "period": {
        "start": "2001-05-06"
      },
      "assigner": {
        "display": "Acme Healthcare"
      }
    }
  ],
  "active": true,
  "name": [
    {
      "use": "official",
      "family": "Chalmers",
      "given": [
        "Peter",
        "James"
      ]
    },
    {
      "use": "usual",
      "given": [
        "Jim"
      ]
    },
    {
      "use": "maiden",
      "family": "Windsor",
      "given": [
        "Peter",
        "James"
      ],
      "period": {
        "end": "2002"
      }
    }
  ]
}
```

Take this graphQL, and apply it to the example:

```
{
  identifier { system value }
  active 
  name { text given family } 
}
```

This will give the output:

```
{
  "identifier": [{
      "system": "urn:oid:1.2.36.146.595.217.0.1",
      "value": "12345"
  }],
  "active": true,
  "name": [{
    "given": ["Peter","James"],
    "family": "Chalmers"
  },{
    "given": ["Jim"]
  },{
    "given": ["Peter","James"],
    "family": "Windsor"
  }]
}
```

Adding the @flatten directive changes the output:

```
{
  identifier @flatten { system value }
  active 
  name @flatten { text given family } 
}
```

This has the output:

```
{
  "system":["urn:oid:1.2.36.146.595.217.0.1"],
  "value":["12345"],
  "active":true,
  "given":["Peter","James","Jim","Peter","James"],
  "family":["Chalmers","Windsor"]
}
```

#### Short cut for selecting only the first element
```
@first
```

This is a shortcut for a FHIR path filter [$index = 0] and indicates to only take the first match of 
the elements. Note that the selection of the first element only applies to the immediate context of 
the field in the source graph, not to the output graph


Example:

```
{
  identifier @flatten { system value }
  active 
  name @flatten { text given @first family } 
}
```

Gives the output:

```
{
  "system":["urn:oid:1.2.36.146.595.217.0.1"],
  "value":["12345"],
  "active":true,
  "given":["Peter","Jim","Peter"],
  "family":["Chalmers","Windsor"]
}
```

#### Managing output cardinality
```
@singleton
```

This directive indicates that an field collates to a single node, not a list. It is only used in association 
with fields on which a parent has @flatten, and overrides the impact of flattening the parent in 
making it a list. The server SHALL return an error if there is more than on value when flattening


Extending the previous example, adding @singleton:

```
{
  identifier @flatten { system @singleton value @singleton }
  active 
  name @flatten @first { text given family @singleton } 
}
```

Gives the output:

```
{
  "system":"urn:oid:1.2.36.146.595.217.0.1",
  "value":"12345",
  "active":true,
  "given":["Peter","James"],
  "family":"Chalmers"
}
```

#### Converting Lists to singletons

```
@slice(fhirpath)
```

This indicates that in the output graph, each element in the source will have "." and the result of 
the FHIRPath as a string appended to the specified name. This slices a list up into multiple single 
values. For example

```
{ name @slice(path: "$index") @flatten {given @first @singleton family}}
```

For a resource that has 2 names will result in the output

```
{
 "Given.0" : "first name, first given",
 "Family.0" : ["first name family name"],
 "Given.1" : "second name, first given",
 "Family.1" : ["second name family name"]
}
```

Other uses might be e.g. Telecom @slice(use) to generate telecom.home for instance.


Notes:


* In general, the intent of @slice is to break a list into multiple singletons. However 
  servers SHALL not treat the outputs as singletons unless this is explicitly specified using @singleton
* The suffixes added by this method are cumulative when nesting e.g. .suffix1.suffix2
* The same general outcome can be achieved by a set of fields, each with an alias 
   and a filter, if the possible values are known in advance


Examples:


```
{
  identifier @flatten { system value }
  active 
  name @flatten @slice(path: "use") { given family @singleton } 
}
```
 produces 
```
{
  "system":["urn:oid:1.2.36.146.595.217.0.1"],
  "value":["12345"],
  "active":true,
  "given.official":["Peter","James"],
  "family.official":"Chalmers",
  "given.usual":["Jim"],
  "given.maiden":["Peter","James"],
  "family.maiden":"Windsor"
}
```

and
```
{
  identifier @flatten { system value }
  active 
  name @flatten @slice(path: "$index") { given family @singleton } 
}
```
 produces 
```
{
  "system":["urn:oid:1.2.36.146.595.217.0.1"],
  "value":["12345"],
  "active":true,
  "given.0":["Peter","James"],
  "family.0":"Chalmers",
  "given.1":["Jim"],
  "given.2":["Peter","James"],
  "family.2":"Windsor"
}
```




