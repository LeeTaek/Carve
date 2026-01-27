# `docc.Chapter`

Organizes related tutorial pages into a chapter on a table of contents page.

- Parameters:
    - name: The name of the chapter. **(required)**

## Overview

Chapters appear on a table of contents page and help provide a sense of context and accomplishment as readers move through your tutorial content.

![A screenshot showing a chapter on a table of contents page.](tutorial-chapter)

Use `Chapter` directives to organize related tutorial pages into groupings. For each chapter, use the `name` parameter to specify a chapter name, and provide some descriptive text. Then, insert `TutorialReference` directives for the tutorial pages each chapter contains. Optionally, use `Image` directives to show images that illustrate the chapters' content.

```
@Tutorials(name: "SlothCreator") {
    
    ...
    
    ...
    
}
````

### Group Related Chapters

If you need a second level of organization on a table of contents page, use `Volume` directives to organize related chapters into volume groupings.

```
@Tutorials(name: "SlothCreator") {
    ...
}
````

### Contained Elements

A chapter can contain the following items:

- **`Image`**: An image that represents the chapter's content. **(optional)**
- **`TutorialReference`**: A reference to a tutorial page. A chapter must contain at least one tutorial page reference. **(optional)**

### Containing Elements

The following items can contain chapters:

* `Tutorials`
* `Volume`

## Topics

### Referencing Tutorials

- `TutorialReference`

### Displaying an Image

- `Image`
