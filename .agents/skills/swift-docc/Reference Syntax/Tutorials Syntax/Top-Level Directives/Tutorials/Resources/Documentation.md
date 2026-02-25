# `docc.Documentation`

Displays a set of documentation links in the resources section of a tutorial's table of contents page.

- Parameters:
    - destination: A URL to a page of related documentation. **(required)**

## Overview

Use the `Documentation` directive to add links to related documentation in the Resources section at the bottom of your tutorial's table of contents page.

DocC renders the URL you specify in the `destination` parameter as a "View more" link at the bottom of the documentation section. Within the directive, add descriptive text and use standard Markdown syntax to provide links to one or more specific documentation pages. At least one specific documentation link within the directive is required.

```
@Tutorials(name: "SlothCreator") {
    
    ...
    
    }
````

You can include documentation alongside other types of resources, like `Downloads`,  `Forums`, `SampleCode`, and `Videos`.

### Containing Elements

The following items can contain documentation resources:

* `Resources`
