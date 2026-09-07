#let blogpost(
  title: none,
  subtitle: none,
  description: none,
  tag: none,
  repo_url: none,
  authors: (),
  bibliography: none,
  body,
) = {
  let project-repo = if repo_url != none {
    repo_url
  } else {
    sys.inputs.at("repo_url", default: "https://github.com/BuzzYbis/article.web")
  }
  let date = datetime.today().display()
  set document(
    title: title,
    author: authors.map(author => author.name),
    description: [#description],
    date: datetime.today(),
    keywords: if tag != none { if type(tag) == array { tag } else { (tag,) } } else { () },
  )

  show align: it => if sys.inputs.at("format", default: "pdf") == "html" { it.body } else { it }

  set page(
    width: 210mm,
    height: auto,
    margin: (left: 2cm, right: 2cm, top: 1cm, bottom: 2.5cm),
    footer: align(center, text(font: "Atkinson Hyperlegible Next", size: 9pt)[
      #line(length: 100%)
      #v(-0.2em)
      The source of this document is available freely at #link(project-repo) under the CC-BY-4.0 license. \
      This text may contain errors or make you react, do not hesitate to contact me about it! \
      Thanks for reading (or listenning)!
    ]),
  )

  set text(font: "STIX Two Text", size: 11pt)
  show math.equation: set text(font: "STIX Two Math")
  show heading: set text(font: "Atkinson Hyperlegible Next")
  show heading: set text(weight: "bold", fill: rgb("#111111"))
  show raw: set text(font: "JuliaMono", size: 10pt)

  set par(
    justify: true,
    leading: 0.60em,
    spacing: 1.2em,
    first-line-indent: 0pt,
  )

  show link: it => underline(
    offset: 2.5pt,
    stroke: 1pt + rgb("#555555"),
    it,
  )

  show heading.where(level: 1): it => {
    it
    v(0.3em, weak: true)
    line(length: 100%, stroke: 0.50pt + rgb("#18284f"))
    v(0.5em, weak: true)
  }

  if sys.inputs.at("format", default: "pdf") == "html" {
    if subtitle != none {
      html.elem("div", attrs: (class: "blogpost-subtitle-raw"))[#subtitle]
    }
    let author-elements = authors.map(a => {
      if "link" in a { link(a.link)[#a.name] } else { a.name }
    })
    if author-elements.len() > 0 {
      html.elem("div", attrs: (class: "blogpost-authors-raw"))[#author-elements.join(", ")]
    }
    html.elem("div", attrs: (class: "blogpost-date-raw"))[#date]
    html.elem("div", attrs: (class: "blogpost-footer-raw"))[
      The source of this document is available freely at #link(project-repo) under the CC-BY-4.0 license. \
      This text may contain errors or make you react, do not hesitate to contact me about it! \
      Thanks for reading (or listenning)!
    ]
  } else {
    align(center, text(font: "Atkinson Hyperlegible Next", weight: "bold", size: 25pt)[#title \ #text(
        size: 20pt,
      )[#subtitle]])
    v(2em, weak: true)
    align(right, text(font: "Atkinson Hyperlegible Next", style: "italic", size: 9pt)[By #strong(authors.map(a => {
        if "link" in a { link(a.link)[#a.name] } else { a.name }
      }).join(", ", last: " and ")) #h(1fr) Updated on: #date])
    v(0.5em, weak: true)
    line(length: 100%)
    v(1.5em, weak: true)
  }

  set heading(numbering: "1.1.")
  if sys.inputs.at("format", default: "pdf") == "html" {
    show outline.entry: it => {
      show underline: it => it.body
      link(it.element.location())[
        #if it.prefix() != none [#it.prefix() ]#it.body()
      ]
    }
  } else {
    show outline.entry: it => {
      show underline: it => it.body
      let custom-inner = [
        #it.body()
        #box(width: 1fr, it.fill)
      ]

      // 2. Create the clickable link using the native indented layout
      link(it.element.location())[
        #it.indented(it.prefix(), custom-inner)
      ]
    }
  }
  outline(
    title: "Table of Contents",
    depth: 2,
    indent: 1.6em,
  )

  v(2em, weak: true)

  body

  if bibliography != none {
    if type(bibliography) == str or type(bibliography) == array {
      std.bibliography(bibliography)
    } else if type(bibliography) == dictionary {
      let path = bibliography.at("path", default: bibliography.at("file", default: none))
      let style = bibliography.at("style", default: "plos")
      if path != none {
        std.bibliography(path, style: style)
      }
    } else {
      bibliography
    }
  }
}

#let mathcode(
  numbered: true, // Toggle numbering on/off
  start: 1, // Choose where the first line starts
  body,
) = block(
  fill: rgb("#f5f5f5"),
  inset: 12pt,
  radius: 4pt,
  width: 100%,
  {
    // 1. Set the code and math fonts to JuliaMono
    set text(font: "JuliaMono", size: 10pt, fill: rgb("#333333"))
    show math.equation: set text(font: "JuliaMono", fill: rgb("#333333"))

    // 2. Syntax Highlighting Magic
    let keywords = "\b(function|while|do|if|then|else|end|return|break)\b"
    show regex(keywords): it => text(weight: "bold", fill: rgb("#000000"), it)

    // 3. Spacing tweak
    set par(spacing: 0.65em)

    // 4. Numbering Logic
    if numbered {
      set enum(
        numbering: n => text(fill: luma(150), size: 9pt)[#n],
        indent: 0pt,
        body-indent: 1em,
        start: start, // Applies the start parameter
      )
      body
    } else {
      // If toggled off, strip the numbering and indent.
      set enum(
        numbering: n => "",
        indent: 0pt,
        body-indent: 0pt,
      )
      body
    }
  },
)
