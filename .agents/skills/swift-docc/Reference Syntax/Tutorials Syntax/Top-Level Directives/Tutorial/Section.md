# `docc.Section`

Displays a grouping of text, images, and tasks on a tutorial page.

- Parameters:
    - title: The name of the section. **(required)**

## Overview

Use a `Section` directive to show a unit of work that consists of text, media (for example images and videos), and tasks on a tutorial page. A tutorial page must includes one or more sections.

![A screenshot showing a section on a tutorial page. The section includes text, an image, and coding steps.](1)

Use the `title` parameter to provide a name for the section. Then, use the `ContentAndMedia` directive to add text and media that introduces the tasks that the reader needs to follow. This directive must be the first directive in the section. You can optionally show additional text and media by inserting a `Stack` directive. A stack contains between one and three horizontally arranged `ContentAndMedia` directives. Finally, add a `Steps` directive to insert a set of tasks for the reader to perform.

```
````

### Contained Elements

A section can contain the following items:

- **`ContentAndMedia`**: A grouping that contains text and an image or video. At least one `ContentAndMedia` directive is required and must be the first element within a section. **(optional)**
- **`Stack`**: A set of horizontally arranged groupings of text and media. **(optional)**
- **`Steps`**: A set of tasks the reader performs. **(optional)**

### Containing Elements

The following pages can include sections:

- `Tutorial`

## Topics

### Introducing a Section

- `ContentAndMedia`

### Displaying Tasks

- `Steps`

### Arranging Content and Media

- `Stack`
