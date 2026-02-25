# `docc.Step`

Defines an individual task the reader performs within a set of steps on a tutorial page.

## Overview

Use the `Step` directive to define a single task the reader performs within a set of steps  on a tutorial page. Provide text that explains what to do, and provide a code listing , an image, or a video that illustrates the step.

![A screenshot showing a step on a tutorial page. The step has instructional text and a corresponding image.](2-a)

    - Tip: Don't number steps. Steps are automatically numbered in the rendered documentation.

### Setting Context for a Step 

To provide additional context about the step, add text before or after the step.

![A screenshot showing a step on a tutorial page. The step is preceded with context-setting text.](2-b)

    The following steps display your customized sloth view in the preview.

    ### Contained Elements

A step contains one the following items:

- **`Code`**: A code listing, and optionally a preview of the expected result, reader sees when they reach the step. **(optional)**
- **`Image`**: An image the reader sees when they reach the step. **(optional)**
- **`Video`**: A video the reader sees when they reach the step. **(optional)**

### Containing Elements

The following items can include a step:

- `Steps`

## Topics

### Displaying Code

- `Code`

### Displaying Media

- `Image`
- `Video`
