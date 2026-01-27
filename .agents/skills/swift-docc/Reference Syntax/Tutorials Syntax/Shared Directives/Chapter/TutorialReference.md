# `docc.TutorialReference`

Adds an individual tutorial page link to a chapter on a table of contents page.

- Parameters:
    - tutorial: A link to a tutorial page, in the format *`[[Tutorial Page File Name]]([TutorialPageFileName].md)`*. For example, *`[Creating Custom Sloths](Creating-Custom-Sloths.md)`*.  **(required)**

## Overview

Use the `TutorialReference` directive in a chapter on a table of contents page to link to a specific tutorial page. Include one `TutorialReference` per chapter. For each, use the `tutorial` parameter to reference the page by name, preceded by the doc: prefix.

```
@Tutorials(name: "SlothCreator") {
    
    ...
    
    ...
    
}
````

### Containing Elements

The following items can include tutorial page references:

* `Chapter`
