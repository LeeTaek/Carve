# `docc.Tutorial`

Displays a tutorial page that teaches your Swift framework or package APIs through interactive coding exercises.

- Parameters:
    - time: An integer value that represents the estimated time it takes to complete the tutorial, in minutes. **(optional)**
    - projectFiles: The name and extension of an archive in your code base, which the reader can download and use or reference while following the tutorial's steps. **(optional)**

## Overview

The `Tutorial` directive defines the structure of an individual tutorial page that teaches your Swift framework or package APIs through a series of interactive steps. Your tutorial can include one or more of these individual tutorial pages, and readers navigate to them from a table of contents page—defined by the `Tutorials` directive.

![A screenshot of the top portion of a tutorial page.](tutorial-page)

### Create the Tutorial File

Use a text editor to add a Tutorial file to your documentation catalog and ensure the filename ends in `.tutorial`. Copy and paste the template below into your editor.

```
```

### Estimate Completion Time

You can give the reader an idea of how long the tutorial page might take to complete by providing an optional estimate in the `time` parameter. Completion time estimates help the reader understand how long they need to set aside to learn your APIs.

```
````

When you provide estimates on your individual tutorial pages, the introduction section on the table of contents page automatically calculates and displays a total-completion time estimate for the entire tutorial.

### Provide Source Material

If you need to add downloadable materials, like sample projects and code examples, for your tutorials, archive them and add them to your documentation catalog. Consider offering a base project to which the reader can add code as they work through the steps, as well as a finished project for comparison with their work.

Project files can reside anywhere in your documentation catalog, but it's good practice to centralize them in a Resources folder. You may want to create a tutorial-specific one if you created a tutorial folder in your documentation catalog.

To share project files with the reader, provide the archive's name and extension in the `projectFiles` parameter.

```
````

### Add an Introduction

A tutorial page begins with an introduction section, defined by an `Intro` directive. The introduction is the first thing a reader sees on the page, so it needs to draw them into the content that follows and let them know what to expect. An introduction includes text and an image that serves as the section's background, or a link to an introduction video.

```
````

### Add Sections of Steps

A tutorial page includes sets of steps the reader performs, and those steps are organized into logical sections. For example, a tutorial might include a section of steps that guides a reader through setting up a Swift package, and another section that covers adding a class to that package.

Define sections using the `Section` directive. You can optionally start with descriptive text and an image or video animation by using the `ContentAndMedia` directive. Once you define a section, you can include steps to perform coding tasks by using the `Steps` directive. See the `Code` directive to learn how to provide code for a step.

```
````

### Check the Reader's Knowledge

At the end of a tutorial page, you can optionally use an `Assessments` directive to create a section that tests the reader's knowledge. An assessment section includes a set of multiple-choice questions. If the reader gets a question wrong, you can provide a hint that points them toward the correct answer so they can try again.

```
