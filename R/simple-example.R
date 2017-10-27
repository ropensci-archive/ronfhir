library(RonFHIR)

# connect to the server
endpoint <- "http://test.fhir.org/r3"
client <- fhirClient$new(endpoint)

# just get a random patient
a <- client$read(location = "Patient/example", summaryType = "true")
a$identifier

# count Patients with gender = male

b <- client$search("Patient", "gender=male", summaryType="count")
b$total

# now, graphql on a resource
# one annoying feature of graphQL is that you can't normalise data, only filter 
c <- client$qraphQL(location = "Patient/example", query = "{id name{given,family}}")
print(c)

# and a graphQL based search
d <- client$qraphQL(location = NULL, query = "{PatientList(name:\"pet\"){name @first @flatten{family,given @first}}}")
print(d)

# now, an operation 
e <- client$operation(resource = "Observation", id = NULL, name = "lastn", parameters = "max=3&patient=Patient/example&category=vital-signs")
print(e)
