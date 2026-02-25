# `docc.SampleCode`

Displays a set of sample code links in the resources section of a tutorial's table of contents page.

- Parameters:
    - destination: A URL to a page of related sample code. **(required)**

## Overview

Use the `SampleCode` directive to add links to related sample code in the Resources section at the bottom of your tutorial's table of contents page.

DocC renders the URL you specify in the `destination` parameter as a "View more" link at the bottom of the sample code section. Within the directive, add descriptive text and use standard Markdown syntax to provide links to one or more more specific sample code pages. At least one specific sample code link within the directive is required.

```
@Tutorials(name: "SlothCreator") {
    
    ...
    
    }
````

You can include sample code links alongside other types of resources, like `Documentation`,  `Downloads`, `Forums`, and `Videos`.

### Containing Elements

The following items can contain sample code resources:

* `Resources`
