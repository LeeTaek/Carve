# `docc.Tutorials`

Displays a table of contents page for readers to navigate the pages of an interactive tutorial.

- Parameters:
    - name: The name of your tutorial. This typically matches the name of the Swift framework or package you're documenting. **(required)**

## Overview

The `Tutorials` directive defines the structure of the table of contents page readers navigate to access individual tutorial pages.

Use a text editor to add a tutorial table of contents file to your documentation catalog. Ensure the filename ends with `.tutorial`, then copy and paste the template below into your editor. Replace the placeholder content provided with custom content.

``` 
@Tutorials(name: "SlothCreator") {
    }
````

Use the `name` parameter to specify the name of your overall tutorial. This appears throughout the tutorial and in the tutorial's URL when published on the web. Next, use the `Intro` directive to introduce the reader to your tutorial through engaging text and imagery. Then, use `Chapter` directives to reference the step-by-step pages. Chapters can also include images.

### Group Related Chapters

Use the `Volume` directive to group related chapters together if you need another level of organization. Volumes can also include images.

```
@Tutorials(name: "SlothCreator") {
    ...
}
````

### Offer Resources for Continued Learning

If your tutorial has related resources, use the `Resources` directive to share them.

```
@Tutorials(name: "SlothCreator") {
    }
````

To walk through the creation of a simple tutorial project from start to finish, see [Building an Interactive Tutorial](../Reference Syntax/Tutorials Syntax/building-an-interactive-tutorial.md).

### Contained Elements

A table of contents page can contain the following items:

- **`Intro`**: Engaging introductory text and an image or video to display at the top of the table of contents page. **(required)**
- **`Chapter`**: A chapter of a tutorial. This links to individual tutorial pages. A table of contents page must include at least one chapter. **(optional)**
- **`Resources`**: A section that contains links to related resources, like downloads, sample code, and videos. **(optional)**
- **`Volume`**: A group of related chapters. **(optional)**

## Topics

### Providing an Introduction

- `Intro`

### Organizing Content

- `Chapter`
- `Volume`

### Sharing Resources

- `Resources`

## See Also

- [Building an Interactive Tutorial](../Reference Syntax/Tutorials Syntax/building-an-interactive-tutorial.md)
