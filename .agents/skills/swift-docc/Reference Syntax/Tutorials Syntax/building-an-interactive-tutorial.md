# Building an Interactive Tutorial

Construct a step-by-step guided learning experience for your Swift framework or package. 

## Overview

A tutorial expands your Swift framework or package's reference documentation with interactive educational content. Create a tutorial by adding a table of contents and individual tutorial pages that walk the reader through coding exercises that teach your APIs.

![Two diagrams representing different pages in a tutorial. On the left, a diagram of a blocked out table of contents page. On the right, a blocked out version of a tutorial page.](building-tutorial)

### Scope Your Tutorial

A good tutorial starts with a well-designed plan of what you're going to teach. When deciding what your tutorial covers, do the following:

* Define Your Audience. Decide whether you're targeting new developers or experienced programmers. Consider what skills you expect readers to have before they start working through the tutorial. Knowing your audience helps you write to their level of knowledge and experience.

* Define Teaching Goals. Consider what you need the reader be able to do after working through your tutorial. Outline everything you expect the reader to learn. Then, use your outline to structure the different parts of your tutorial.

* Define the Scope. Think about what the reader actually does to learn the concepts you defined. A tutorial needs to be engaging and produce a sense of accomplishment. Identify specific tasks the reader can perform and projects they can build.

### Prepare Your Code Project

In order to prepare your framework or package project for a tutorial, you need a documentation catalog. If your code base's folder doesn't have a documentation catalog, learn how to add one in [Documenting a Swift Framework or Package](../documenting-a-swift-framework-or-package.md). Inside the documentation catalog, add a folder for your tutorial content. By default, a documentation catalog includes a Resources folder. This is where you place tutorial images, code-listing files, and other assets.

### Add a Table of Contents Page

A table of contents page sets context and introduces the reader to your tutorial. It needs to provide enough information that the reader can gain a solid understanding of what your APIs do, before they start performing tutorial steps. The table of contents also organizes your tutorial pages into chapters so readers can browse and navigate to them.

Use a text editor and the following listing to create a table of contents file named `Table Of Contents.tutorial`.

```
@Tutorials(name: "Add the name of your tutorial here. This usually matches your framework name.") {
    }
````

The top level of the listing the includes a `Tutorials` directive. This directive, and the directives it contains, define the structure of the page.

Rename the table of contents file and replace the placeholder content with your custom content. Use the `Intro` directive to introduce the reader to your tutorial through engaging text and imagery. Next, use `Chapter` directives to reference the step-by-step pages.

For more information about table of contents pages, see `Tutorials`.

### Add Step-By-Step Pages

Tutorial pages provide instructions that walk through using your APIs in realistic ways. A tutorial project can include a single tutorial page, or many. Create a new tutorial page using your favorite editor. Give the file a name and add the `.tutorial` extension, then copy the following template into the file.

```
```

Replace the placeholders with your custom content. Use the `Intro` directive to introduce the reader to the page's content, `Steps` directives to define steps the reader follows, and `Section` directives to organize the steps into related groups. For example, your tutorial might include a section of steps that walks through creating something, and another section that walks through customizing it. At the end of each tutorial page, you can optionally use an `Assessments` directive to test the reader's knowledge. See the `Code` directive to learn how to provide code for a step.

```
