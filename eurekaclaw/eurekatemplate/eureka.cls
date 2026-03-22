\NeedsTeXFormat{LaTeX2e}
\ProvidesClass{eureka}

\newcommand{\macframecolordef}{\definecolor{eurekaframe}{HTML}{0666B0}}
\newcommand{\macaccentcolordef}{\definecolor{eurekaaccent}{HTML}{0666B0}}
\newcommand{\macaccenttext}[1]{{\bfseries\color[HTML]{0666B0} #1}}

% =============================================================================
% Public responsibility:
% 1. Load all shared packages and layout rules.
% 2. Expose shared front-matter and header/footer configuration APIs.
% 3. Keep all theme-independent visual logic in one place.
%
% Theme wrappers are expected to define:
% - \macframecolordef
% - \macaccentcolordef
% - \macaccenttext
% =============================================================================

\@ifundefined{macframecolordef}{\ClassError{\@classname}{Missing theme hook \string\macframecolordef}{Define it in the theme .cls before loading main.tex}}{}
\@ifundefined{macaccentcolordef}{\ClassError{\@classname}{Missing theme hook \string\macaccentcolordef}{Define it in the theme .cls before loading main.tex}}{}
\@ifundefined{macaccenttext}{\ClassError{\@classname}{Missing theme hook \string\macaccenttext}{Define it in the theme .cls before loading main.tex}}{}

\LoadClassWithOptions{article}
\RequirePackage{iftex}
\ifdefined\pdfoutput
\pdfoutput=1
\fi

% =============================================================================
% Core packages and layout
% =============================================================================

\RequirePackage[top=2.12cm, bottom=3.20cm, left=2.5cm, right=2.5cm, columnsep=0.65cm]{geometry}
\ifXeTeX\else
\RequirePackage[expansion=false]{microtype}
\fi
\RequirePackage{placeins}
\RequirePackage{setspace}
\RequirePackage{parskip}
\RequirePackage[english]{babel}
\RequirePackage{lipsum}
\RequirePackage{etoolbox}
\RequirePackage{enumitem}
\newcommand{\nohyphens}{\hyphenpenalty=10000\exhyphenpenalty=10000\relax}

\RequirePackage{fancyhdr}
\ifdefined\pdfoutput
\DisableLigatures[f]{family=sf*}
\fi

% =============================================================================
% Graphics
% =============================================================================

\RequirePackage{graphicx}
\RequirePackage[export]{adjustbox}
\RequirePackage{subcaption}

% =============================================================================
% Tables
% =============================================================================

\RequirePackage{booktabs}
\RequirePackage{nicematrix}
\RequirePackage{multirow}
\RequirePackage{makecell}
\RequirePackage{colortbl}
\RequirePackage{bm}
\RequirePackage{amsmath}
\RequirePackage{amssymb}
\RequirePackage{algorithm}
\RequirePackage{algorithmic}
\RequirePackage{pifont}
\RequirePackage{marvosym}
\newcommand{\nm}[1]{#1}

% =============================================================================
% Theme colors
% =============================================================================

\RequirePackage[most]{tcolorbox}
\RequirePackage{xcolor}
\macframecolordef
\macaccentcolordef
\newcommand{\eurekaaccent}[1]{\macaccenttext{#1}}
\definecolor{black}{rgb}{0,0,0}
\newcommand{\black}[1]{{\bfseries\color[HTML]{000000} #1}}

% =============================================================================
% References
% =============================================================================

\RequirePackage{hyperref}
\RequirePackage{xurl}
\RequirePackage[noabbrev,nameinlink]{cleveref}
\hypersetup{
  colorlinks,
  linkcolor=eurekaaccent,
  citecolor=eurekaaccent,
  urlcolor=eurekaaccent
}

\RequirePackage[numbers, sort&compress]{natbib}
\def\bibfont{\small}
\emergencystretch=1.5em
\hbadness=2000

% =============================================================================
% Bibliography
% =============================================================================
\addto{\captionsenglish}{\renewcommand{\refname}{References}}
\newcommand{\citeas}[1]{\Needspace*{8\baselineskip}\noindent\bibentry{#1}}

% =============================================================================
% Section and caption style
% =============================================================================

\newcommand{\sectionfont}
{\fontsize{13}{14}\selectfont}

\newcommand{\subsectionfont}
{\fontsize{11}{13}\selectfont}

\RequirePackage{titlesec}
\titleformat*{\paragraph}{\itshape}
\titleformat*{\section}{\sectionfont\sffamily\bfseries\eurekaaccent}
\titleformat*{\subsection}{\subsectionfont\sffamily\bfseries\eurekaaccent}
\titleformat*{\subsubsection}{\normalsize\sffamily\bfseries\eurekaaccent}
\titlespacing*{\section}{0pt}{3ex plus4pt minus3pt}{5pt}
\titlespacing*{\subsection}{0pt}{2.5ex plus3pt minus2pt}{2pt}
\titlespacing*{\subsubsection}{0pt}{2ex plus2.5pt minus1.5pt}{2pt}

\RequirePackage{caption}
\DeclareCaptionLabelSeparator{period}{. }
\captionsetup{
  labelfont={bf,sf},
  labelsep=period,
  figurename=Figure,
  tablename=Table,
  format=plain,
  singlelinecheck=off,
  justification=raggedright,
  font=small
}
\captionsetup[figure]{
  skip=6pt,
  format=plain,
  singlelinecheck=off,
  justification=raggedright
}
\captionsetup[table]{
  skip=4pt,
  format=plain,
  singlelinecheck=off,
  justification=raggedright
}

\ifXeTeX
  \RequirePackage{fontspec}
  \setmainfont[
    SmallCapsFeatures = {Letters=SmallCaps}
  ]{TeX Gyre Termes}
  \setsansfont{Noto Sans}
  \setmonofont{Noto Sans Mono}
  \newfontfamily\bytesansmedium[
    Path = fonts/,
    Extension = .ttf,
    UprightFont = ByteSans-Medium,
    BoldFont = ByteSans-Bold
  ]{ByteSans-Medium}
  \newfontfamily\eurekatitlefont[
    Path = fonts/,
    Extension = .ttf,
    UprightFont = ByteSans-Bold,
    BoldFont = ByteSans-Bold
  ]{ByteSans-Bold}
  \newfontfamily\eurekaheadingfont[
    Path = fonts/,
    Extension = .ttf,
    UprightFont = ByteSans-Bold,
    BoldFont = ByteSans-Bold
  ]{ByteSans-Bold}
  \newfontfamily\eurekaauthorfont[
    Path = fonts/,
    Extension = .ttf,
    UprightFont = ByteSans-Bold,
    BoldFont = ByteSans-Bold
  ]{ByteSans-Bold}
  \newfontfamily\eurekaaffiliationfont[
    BoldFont = {Noto Sans SemiBold}
  ]{Noto Sans}
  \newfontfamily\eurekaemailfont[
    BoldFont = {Noto Sans SemiBold}
  ]{Noto Sans}
  \newfontfamily\eurekamonofont{Noto Sans Mono}
\else
  \RequirePackage[T1]{fontenc}
  \renewcommand{\sfdefault}{lmss}%
  \renewcommand{\rmdefault}{cmr}
\fi

% =============================================================================
% Front-matter data model
% =============================================================================

\renewcommand\addtolist[5][]{
  \begingroup
    \if\relax#3\relax\def\sep{}\else\def\sep{#5}\fi
    \let\protect\@unexpandable@protect
    \xdef#3{\expandafter{#3}\sep #4[#1]{#2}}%
  \endgroup
}

\newcommand{\authorfont}
{\fontsize{12}{14}\selectfont}

\newcommand{\authorgroupfont}
{\fontsize{9.1}{10.8}\selectfont}
\newcommand{\affmark}[1]{\textsuperscript{#1}}

\newcommand\authorlist{}
\ifXeTeX
\newcommand\authorformat[2][]{\authorfont {\color{black!84}\eurekaauthorfont\bfseries #2\affmark{#1}}}
\else
\newcommand\authorformat[2][]{\authorfont {\color{black!82}\sffamily\mdseries #2\affmark{#1}}}
\fi
\renewcommand\author[2][]{\addtolist[#1]{#2}{\authorlist}{\authorformat}{, }}

\newcommand{\affiliationfont}
{\fontsize{10}{12}\selectfont}

\newcommand\affiliationlist{}
\ifXeTeX
\newcommand\affiliationformat[2][]{{\affiliationfont {\eurekaaffiliationfont \affmark{#1}#2}}}
\else
\newcommand\affiliationformat[2][]{{\affiliationfont {\sffamily \affmark{#1}#2}}}
\fi
\newcommand\affiliation[2][]{\addtolist[#1]{#2}{\affiliationlist}{\affiliationformat}{, }}

\newcommand{\contributionfont}
{\fontsize{9.6}{12}\selectfont}

\newcommand\contributionlist{}
\newcommand\contributionformat[2][]{{\contributionfont \affmark{#1}#2}}
\newcommand\contribution[2][]{\addtolist[#1]{#2}{\contributionlist}{\contributionformat}{, }}

\newcommand{\emailfont}
{\fontsize{8.2}{10.4}\selectfont}

\newcommand\emaillist{}
\ifXeTeX
\newcommand\emails[1]{\def\emaillist{{\emailfont\color{black!60}\eurekaemailfont #1}}}
\else
\newcommand\emails[1]{\def\emaillist{{\emailfont\color{black!65}\ttfamily #1}}}
\fi

\newcommand{\checkdatafont}
{\fontsize{7.92}{10}\selectfont}

\newcommand\checkdatalist{}
\newcommand\checkdataformat[2][]{{\small {\checkdatafont\sffamily \bfseries #1:} #2}}
\newcommand\checkdata[2][]{\addtolist[#1]{#2}{\checkdatalist}{\checkdataformat}{\par}}

\newcommand{\abstractinfont}
{\fontsize{10}{12}\selectfont}

\renewcommand{\abstract}[1]{\def\abstractlist{{\abstractinfont #1}}}
\newcommand{\email}[1]{\href{mailto:#1}{\texttt{#1}}}
\newcommand{\corremailmark}{\Letter}
\newcommand{\authormark}[1]{\textsuperscript{#1}}
\newcommand{\authorentry}[2]{\mbox{#1\authormark{#2}}}
\newcommand{\authorsep}{\hspace{0.78em}}
\newcommand{\authorrow}[1]{\makebox[\linewidth][c]{#1}\par\vspace{2.2pt}}
\newcommand{\affiliationline}[1]{#1\par}
\newcommand{\contactline}[1]{#1\par}

\newcommand{\macauthorrows}{}
\newcommand{\macaffiliationrows}{}
\newcommand{\maccontactrows}{}

% Public front-matter configuration API.
\newcommand{\setauthorrows}[1]{\gdef\macauthorrows{#1}}
\newcommand{\setaffiliationrows}[1]{\gdef\macaffiliationrows{#1}}
\newcommand{\setcontactrows}[1]{\gdef\maccontactrows{#1}}
\newcommand{\usecustomauthorlayout}{
  \def\authorlist{%
    {\fontsize{12}{14}\selectfont\color{black!96}%
    \ifXeTeX\eurekaauthorfont\bfseries\else\sffamily\bfseries\fi
    \parbox{0.96\linewidth}{\centering \macauthorrows}}}
  \def\affiliationlist{%
    {\fontsize{9.9}{11.9}\selectfont\color{black!70}%
    \ifXeTeX\bytesansmedium\else\sffamily\fi
    \parbox{0.92\linewidth}{\centering
    \macaffiliationrows\par
    \vspace{2.8mm}
    {\fontsize{9.8}{11.8}\selectfont\color{black!82}%
    \ifXeTeX\bytesansmedium\else\sffamily\fi
    \maccontactrows}}}}
  \def\emaillist{{}}}
\newcommand{\setfrontauthors}[1]{\setauthorrows{#1}}
\newcommand{\setfrontaffiliations}[1]{\setaffiliationrows{#1}}
\newcommand{\setfrontcontact}[1]{\setcontactrows{#1}}

\renewcommand\date[1]{\checkdata[Date]{#1}}
\newcommand\correspondence[1]{\checkdata[Correspondence]{#1}}

\newcommand{\titlefont}
{\fontsize{17}{20}\selectfont}

\ifXeTeX
\renewcommand{\title}[1]{\newcommand{\titlelist}{\parbox{0.945\linewidth}{\centering\titlefont{\eurekatitlefont\bfseries #1}}}}
\else
\renewcommand{\title}[1]{\newcommand{\titlelist}{\parbox{0.92\linewidth}{\centering\titlefont{\sffamily\bfseries #1}}}}
\fi

\newcommand{\abstractfont}
{\fontsize{12}{12}\selectfont}

\ifXeTeX
\newcommand{\beginabstract}{\abstractfont{\eurekaauthorfont\bfseries\color{eurekaaccent!88!black}Abstract}}
\else
\newcommand{\beginabstract}{\abstractfont{\sffamily\bfseries\color{eurekaaccent}\MakeUppercase{Abstract}}}
\fi

\newcommand{\beginappendix}{\appendix{\titlefont\sffamily \eurekaaccent{Appendix}\par}}
\colorlet{abstractboxfill}{white}

% =============================================================================
% Reusable document-level utilities
% =============================================================================

\newcommand{\macparagraph}[1]{\par\vspace{2pt}\noindent\textbf{#1}\hspace{1.8ex}}
\definecolor{macgreen}{RGB}{34,139,34}
\definecolor{macred}{RGB}{220,20,60}
\definecolor{macorange}{RGB}{255,140,0}
\newcommand{\cmark}{\textcolor{macgreen}{\ding{51}}}
\newcommand{\xmark}{\textcolor{macred}{\ding{55}}}
\newcommand{\pmark}{\textcolor{macorange}{\raisebox{0.12ex}{\footnotesize\textasciitilde}}}
\newcommand{\fb}{\makebox[0.5em][c]{\textbullet}}
\newcommand{\eb}{\makebox[0.5em][c]{\textopenbullet}}
\newcommand{\eg}{e.g.,\ }
\newcommand{\ie}{i.e.,\ }

\tcbuselibrary{skins}
\tcbset{
  aibox/.style={
    width=\linewidth,
    top=7pt,
    bottom=2pt,
    colback=blue!4!white,
    colframe=black,
    colbacktitle=black,
    enhanced,
    center,
    attach boxed title to top left={yshift=-0.1in,xshift=0.15in},
    boxed title style={boxrule=0pt,colframe=white,},
  }
}
\newtcolorbox{AIbox}[2][]{aibox,title=#2,#1}

% =============================================================================
% branding configuration
% =============================================================================

\newcommand{\macleftheadercontent}{}
\newcommand{\macrightheadericon}{}
\newcommand{\macrunningheadericon}{}
\newcommand{\macheadertextcontent}{Eureka}

\newcommand{\setleftheadercontent}[1]{\gdef\macleftheadercontent{#1}}
\newcommand{\setrightheadericon}[1]{\gdef\macrightheadericon{#1}}
\newcommand{\setrunningheadericon}[1]{\gdef\macrunningheadericon{#1}}
\newcommand{\setheadergroupname}[1]{\gdef\macheadertextcontent{#1}}
\newcommand{\headerlogo}[3][0pt]{\raisebox{#1}{\includegraphics[height=#2]{#3}}}
\newcommand{\headerlogospace}[1]{\hspace*{#1}}

% Public header/footer configuration API.
\newcommand{\firstpageheaderlogos}{%
  \makebox[\textwidth][s]{%
    \macleftheadercontent\hfill\macrightheadericon
  }%
}
\ifXeTeX
\newcommand{\eurekaheadertext}{{\eurekaauthorfont\fontsize{8.1}{10}\selectfont\color{black!58}\addfontfeatures{LetterSpace=4}\macheadertextcontent}}
\else
\newcommand{\eurekaheadertext}{\sffamily\fontsize{8.1}{10}\selectfont\color{black!60} \macheadertextcontent}
\fi
\fancypagestyle{firststyle}{
    \fancyhead[L]{
        \vskip 0.8mm
        \firstpageheaderlogos
    }
    \fancyhead[R]{}
}
\pagestyle{fancy}
\fancyhf{}
\fancyhead[L]{
  \vskip 2.5mm
  \macrunningheadericon
}
\fancyhead[R]{
  \vskip 4.2mm
  \eurekaheadertext
}
\fancyfoot[C]{\sffamily\fontsize{8.6}{10}\selectfont\thepage}

\renewcommand{\headrulewidth}{0pt}
\renewcommand{\footrulewidth}{0pt}
\setlength{\headheight}{64pt}
\setlength{\headsep}{6pt}
\setlength{\footskip}{18pt}

% =============================================================================
% Title and abstract box implementation
% =============================================================================
\newcommand{\@toptitlebar}{
  {\color{eurekaaccent!88!black}\hrule height 2.4pt}
  \vskip 6mm
}
\newcommand{\@bottomtitlebar}{
  \vskip 6mm
  {\color{eurekaaccent!88!black}\hrule height 2.4pt}
}

% Titlebox %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

\newcommand{\mymaketitle}{%
  \tcbset{enhanced}
  \tcbset{left=8mm}
  \tcbset{right=8mm}
  \tcbset{top=4.0mm}
  \tcbset{bottom=3.8mm}
  \tcbset{colback=white}
  \tcbset{colframe=eurekaframe}
  \tcbset{boxrule=3pt}
  \tcbset{before skip=0pt}
  \tcbset{grow to left by=1.5pt}
  \tcbset{grow to right by=1.5pt}
  \tcbset{arc=2.2mm}
      {
      \setlength{\parskip}{0mm}
      \hfuzz=20pt
      \hbadness=10000
      \centering
      \nohyphens

      {
      \vspace*{-4.8mm}
      \@toptitlebar

        \titlelist\par
         \@bottomtitlebar
      }
      \vskip 4.0mm
      \authorlist
      \vskip 2.4mm

      \affiliationlist\par
      \ifdefempty{\emaillist}{}{\vskip 3mm \emaillist\par}

      \contributionlist\par
    }
   \vskip 2.6mm

  \begin{tcolorbox}[
    enhanced jigsaw,
    colback=abstractboxfill,
    colframe=eurekaaccent!99,
    boxrule=1.6pt,
    arc=2.5mm,
    left=8mm,
    right=8mm,
    top=4.1mm,
    bottom=4.2mm,
    interior style={fill=abstractboxfill},
    drop shadow={black!12!white},
    before skip=0pt,
    after skip=0pt
  ]
    \setlength{\parindent}{0cm}
    \setlength{\parskip}{0cm}

    \begin{center}
      \beginabstract
      \vskip 1.8mm
    \end{center}

    \abstractlist\par
    \vskip 0.6mm
    {
      \setlength{\parskip}{0cm}
      \ifdefempty{\checkdatalist}{\vspace*{0.02cm}}{\checkdatalist\par}
    }
  \end{tcolorbox}
  \tcbset{reset}
  \FloatBarrier

  \thispagestyle{firststyle}
}

\if@twocolumn%
\renewcommand{\maketitle}{
\twocolumn[%
 \vskip 2mm
  \mymaketitle
  \vskip 4mm
]
}%
\else%
\renewcommand{\maketitle}{
  \mymaketitle
  \vskip 4mm
}%
\fi

