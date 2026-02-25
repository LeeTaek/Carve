# `docc.Videos`

Displays a set of video links in the resources section of a tutorial's table of contents page.

- Parameters:
    - destination: A URL to a page of related videos. **(required)**

## Overview

Use the `Videos` directive to add links to related videos in the Resources section at the bottom of your tutorial's table of contents page.

DocC renders the URL you specify in the `destination` parameter as a "Watch videos" link at the bottom of the sample code section. Within the directive, add descriptive text and, optionally, use standard Markdown syntax to provide links to one or more more specific videos.

A single "Watch videos" link:

```
@Tutorials(name: "SlothCreator") {
    
    ...
    
    }
````

A "Watch videos" link with additional specific video links: 

```
@Tutorials(name: "SlothCreator") {
        
    ...
    
    }
````

You can include video links alongside other types of resources, like `Documentation`,  `Downloads`, `Forums`, and `SampleCode`.

### Containing Elements

The following items can contain video resources:

* `Resources`
