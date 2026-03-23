# `docc.ContentAndMedia`

Displays a grouping that contains text and an image or a video in a section on a tutorial page.

## Overview

Use a `ContentAndMedia` directive within a `Section` or `Stack` directive to display a grouping that contains text and an image or a video. Set the `layout` parameter's value to `"horizontal"`. Then, provide one or more paragraphs of text, followed by an `Image` or `Video` directive.

```
````

### Contained Elements

A content and media element must contain one of the following items:

- **`Image`**: An image to display. **(optional)**
- **`Video`**: A video to display. **(optional)**

### Containing Elements

The following items can include a content and media element:

- `Section`
- `Stack`

## Topics

### Displaying Media

- `Image`
- `Video`
