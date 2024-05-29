# C++ to SVG Converter

I originally started this to learn ZIG Lang.

## Overview

This program is a C++ to SVG converter. It takes C++ code as input and generates a corresponding SVG (Scalable Vector
Graphics) image. This can be particularly useful for visualizing code flow, creating documentation, or sharing your code
in a more visual and engaging way.

## Features

- **Code to SVG**: Convert your C++ code into a visually appealing SVG image.
- **Syntax Highlighting**: The generated SVG will have syntax highlighting similar to most modern code editors, making
  the code easier to read and understand.
- **Customizable Themes**: The program supports both light and dark themes. You can switch between themes based on your preference.

## Installation

To install the program, follow these steps:

1. Clone the repository: `git clone https://github.com/yourusername/cpp-to-svg.git`
2. Navigate to the project directory: `cd cpp-to-svg`
3. Compile the program: `g++ -o cpp_to_svg main.cpp`

## Usage

To convert a C++ file to SVG, use the following command:

```bash
./CodeToSVG -f input.cpp -o output.svg -s style.yml
```

## Help wanted with...
- Detecting long strings `/*...*/`;
- Detecting function calls;
- Detecting function definitions;
- Detecting usages of custom enums, struts, and classes;
- Better formatting;
- Making it compatible with more languages than just C++;
- Providing more styles;
- Write tests to ensure this program keeps running correctly.
 