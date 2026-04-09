\NeedsTeXFormat{LaTeX2e}
% \RequirePackage{expl3}

\ProvidesClass{hcmut_report}

\DeclareOption*{\PassOptionsToClass{\CurrentOption}{article}}
\ProcessOptions\relax
\LoadClass[a4paper]{article}

% Set up font
\RequirePackage[fontsize=12pt]{scrextend}
\RequirePackage[utf8]{vntex}
\RequirePackage[T5]{fontenc}
\RequirePackage{mathptmx} % Apply Times New Roman font
\RequirePackage{anyfontsize,amsmath,amssymb} % Fonts for math environment
\RequirePackage[vietnamese=nohyphenation]{hyphsubst} % Ignore a warning
\RequirePackage[vietnamese]{babel} % Support Vietnamese text

% Packages
\RequirePackage{fancyhdr,hyperref}
\RequirePackage[super,square,sort]{natbib}
\RequirePackage{tikz}
\usetikzlibrary{calc}
\RequirePackage{pgffor} % For loops
\RequirePackage{xstring} % For string manipulation
\RequirePackage{extramarks}
\usepackage{listings}
\usepackage{color} % tô màu cho code
\usepackage{tikz, tcolorbox}

% Some packages that seem pretty redundant
\RequirePackage{geometry,graphicx,indentfirst,setspace}
\RequirePackage{booktabs}
\RequirePackage{caption,subcaption}

\RequirePackage{fancyhdr,hyperref}
\RequirePackage[super,square,sort]{natbib}

% Indentation
\setlength{\parindent}{1pt}

% Define some default names and a corresponding command to update them
\newcommand{\@upperuniname}{Vietnam National University Ho Chi Minh City}
\newcommand{\upperuniname}[1]{\renewcommand{\@upperuniname}{#1}}

\newcommand{\@uniname}{Ho Chi Minh City University of Technology}
\newcommand{\uniname}[1]{\renewcommand{\@uniname}{#1}}

\newcommand{\@deptname}{Faculty of Computer Science and Engineering}
\newcommand{\deptname}[1]{\renewcommand{\@deptname}{#1}}

\newcommand{\@coursename}{Course name}
\newcommand{\coursename}[1]{\renewcommand{\@coursename}{#1}}

\newcommand{\@reporttype}{Assignment Report}
\newcommand{\reporttype}[1]{\renewcommand{\@reporttype}{#1}}
\definecolor{dkgreen}{rgb}{0,0.6,0}
\definecolor{gray}{rgb}{0.5,0.5,0.5}
\definecolor{mauve}{rgb}{0.58,0,0.82}
\definecolor{backcolour}{rgb}{0.97, 0.97, 0.92}
\lstset{
  frame=tb,
  language= C,
%   aboveskip=3mm,
%   belowskip=3mm,
    backgroundcolor=\color{backcolour},
  showstringspaces=false,
  columns=flexible,
  basicstyle={\small\ttfamily},
  numbers=none,
  numberstyle=\tiny\color{gray},
  keywordstyle=\color{blue},
  commentstyle=\color{dkgreen},
  stringstyle=\color{mauve},
  breaklines=true,
  breakatwhitespace=true,
  tabsize=3
}
\title{Report title}

% More arguments: top, bottom, left, right
\geometry{
  paper=a4paper,
  left=2cm,
  right=2cm,
  vmargin=2cm, % Set for both top and bottom
  includeheadfoot=true,
  headheight=35pt
}

\onehalfspacing
\raggedbottom
\renewcommand{\arraystretch}{1.3}

% Set depth of numbering for sections and table of contents
\setcounter{secnumdepth}{3}
\setcounter{tocdepth}{3}

% Set depth of numbering for counters
\AtBeginDocument{\counterwithin{equation}{section}}
\AtBeginDocument{\counterwithin{table}{section}}
\AtBeginDocument{\counterwithin{figure}{section}}

\AtBeginDocument{\renewcommand*\bibname{References}}

\hypersetup{
  colorlinks=true,
  linkcolor=black,
  citecolor=red,
  urlcolor=blue
}

% Set up fancyhdr
% Line
\renewcommand{\headrulewidth}{0pt} 
\renewcommand{\footrulewidth}{0.4pt}

\pagestyle{fancy}
\fancyhf{}

\if@twoside
    % --- BỎ ĐOẠN FOOTER CŨ VÀ THAY BẰNG ĐOẠN MỚI ---
    % Trang chẵn (Even pages)
    \fancyfoot[LE]{\thepage} % Số trang bên trái
    \fancyfoot[RE]{\it{Microcontroller}} % Chữ bên phải

    % Trang lẻ (Odd pages)
    \fancyfoot[LO]{\it{HCMUT - Computer Engineering}} % Chữ bên trái
    \fancyfoot[RO]{\thepage} % Số trang bên phải
\else
    \fancyhead[R]{
        \bfseries
        \begin{tabular}{rl}
        \begin{tabular}{r}
            \ttfamily\@uniname \\
            \ttfamily\@deptname \\
        \end{tabular}
        \begin{picture}(25pt,15pt)
            \put(0,-8pt){\includegraphics[width=15pt]{graphics/hcmut.png}}
        \end{picture}
        \end{tabular}
    }
\fi

\fancyfoot[LE]{Page \thepage}
\fancyfoot[RO]{Page \thepage}
%------------------------------------------------------------------------------------------------------------------------%
\newcommand{\coverpage}{
    
    \begin{tikzpicture}[overlay,remember picture]
        \draw [line width=3pt]        
            ($ (current page.north west) + (2.5cm,-1.5cm) $)
            rectangle
            ($ (current page.south east) + (-1.5cm,1.5cm) $);        
        \draw [line width=0.5pt]
            ($ (current page.north west) + (2.6cm,-1.6cm) $)
            rectangle
            ($ (current page.south east) + (-1.6cm,1.6cm) $);
    \end{tikzpicture}

    \pagestyle{empty}

    \vspace*{-3\baselineskip}
    \begin{center}
        % --- XÓA DÒNG NÀY ĐỂ BỎ TÊN "VIETNAM NATIONAL..." ---
        % \MakeUppercase{\@upperuniname} 

        \MakeUppercase{\@uniname}

        \MakeUppercase{\@deptname}
        \vfill
        \includegraphics[scale=0.4]{graphics/hcmut.png}
        \vfill
        \bfseries
        \begin{tabular}{c}
        \Large\@coursename                                 \\
                                                        
        \midrule                                          \\ 
        \Large\@reporttype                                  \\
        {}                                                 \\
        \Huge\parbox[c]{0.8\linewidth}{\centering \@title} \\
        {}                                                 \\
        \bottomrule
        \end{tabular}
        \vfill
        \mdseries
        \begin{tabular}{llr}
            
             Advisor:   \@advisor 
            Student:  \@student 
        \end{tabular}
        \vfill
        Ho Chi Minh City, September 23, 2025
    \end{center}
    \cleardoublepage
    \pagestyle{fancy}
}

\ExplSyntaxOn 
\NewDocumentCommand{\advisor}{+v}{
    \seq_set_split:Nnn \l_tmpa_seq { \obeyedline } {#1}    
    \seq_remove_all:Nn \l_tmpa_seq {}
    
    \tl_const:Ne \l_advisor_name_tl {& \seq_use:Nn \l_tmpa_seq {} & \\}   

    \newcommand{\@advisor}{\tl_use:N \l_advisor_name_tl}    
}

\NewDocumentCommand{\student}{+v}{
    \seq_set_split:Nnn \l_tmpa_seq { \obeyedline } {#1}
    \seq_remove_all:Nn \l_tmpa_seq {}

    \tl_clear_new:N \l_student_list_tl    

    \seq_map_inline:Nn \l_tmpa_seq {
        \seq_set_split:Nnn \l_tmpb_seq { , } {##1}        
        \tl_put_right:Ne \l_student_list_tl { & \seq_use:Nn \l_tmpb_seq { & } \\}        
    }    
    \newcommand{\@student}{\tl_use:N \l_student_list_tl}
}
\ExplSyntaxOff