%% The Corelatus Blog is written in plain HTML.
%%
%% This script takes src/*.html and turns it into a blog article.
%%
%% A blog article uses the same format as 'chronicle', i.e.
%%
%%    Title: the article title
%%    Tags: a list of tags
%%    Date: 7. May 2014
%%    (a blank line)
%%    (the HTML body)
%%

-module(make_blog).
-export([go/0]).

-record(article, {title="",
		  tags=[],
		  date::{integer(), integer(), integer()},
		  filename,
		  body}).

go() ->
    Config = read_config(),
    Unsorted = read_articles(),
    Articles = lists:reverse(lists:keysort(#article.date, Unsorted)),
    emit_first_page(Config, Articles),
    emit_permalinks(Config, Articles),
    emit_tagged(Config, Articles),
    init:stop().

read_config() ->
    case file:consult("config") of
	{ok, Terms} ->
	    check_config(Terms),
	    Terms;
	X ->
	    io:fwrite("Reading the config file failed: ~p\n", [X]),
	    exit(config_bad)
    end.

check_config(Terms) ->
    Expected = [title, subtitle, about, output],
    Actual =   [Key || {Key, _} <- Terms],
    Only_in_config = Actual -- Expected,
    Missing_in_config = Expected -- Actual,

    Only_in_config == []
	orelse io:fwrite("Warning: bogus keys in config: ~p\n",
			 [Only_in_config]),

    Missing_in_config == []
	orelse exit({"Missing keys in config", Missing_in_config}).

read_articles() ->
    Dir = "src/",
    Filenames = [Dir ++ X || X <- filelib:wildcard("*.html", Dir)],
    Regular_files = lists:filter(fun filelib:is_regular/1, Filenames),
    io:fwrite("Reading ~p articles\n", [length(Regular_files)]),
    lists:map(fun read_article/1, Regular_files).

read_article(Filename) ->
    try
	{ok, F} = file:open(Filename, [read]),
	{"Title", Title} = read_header(F),
	{"Tags", Tags} = read_header(F),
	{"Date", Date} = read_header(F),
	blank_line = read_header(F),
	{ok, Body} = file:read(F, 9999999),
	Tag_list = lists:map(fun string:strip/1, string:tokens(Tags, ",")),
	#article{title = Title,
		 tags = Tag_list,
		 date = parse_date(Date),
		 filename = title_to_filename(Title),
		 body = escape_code(Body)}

    catch Class:Type ->
	    io:fwrite("Failed while reading ~s\n", [Filename]),
	    exit({Class, Type})
    end.

read_header(F) ->
    {ok, Line} = file:read_line(F),
    case Line of
	"\n" ->
	    blank_line;
	_ ->
	    Colon = string:chr(Line, $:),
	    Key = string:substr(Line, 1, Colon-1),
	    Value = string:substr(Line, Colon+1),
	    {Key, string:strip(string:strip(Value, both, $\n))}
    end.

%% The <code> tag is a fake tag. It tells us that all <> and other
%% characters HTML considers special need to be rewritten.
escape_code(Body) ->
    case string:str(Body, "<code") of
	0 ->
	    Body;
	N ->
	    Before = string:substr(Body, 1, N-1),
	    After = string:substr(Body, N),
	    End = string:chr(After, $>),
	    Close = string:str(After, "</code>"),

	    Needs_escaping = string:substr(After, End + 1, Close - End - 1),
	    After_escaping = string:substr(After, Close),

	    Close_end = string:chr(After_escaping, $>),
	    Remaining = string:substr(After_escaping, Close_end + 1),

	    [Before, escape_chars(Needs_escaping), escape_code(Remaining)]
    end.

escape_chars(String) ->
    F = fun($>) -> "&gt;";
	   ($<) -> "&lt;";
	   ($&) -> "&amp;";
	   (X) -> X
	end,
    lists:map(F, String).

%% The canonical URL for an article is just its title, with all weird
%% characters replaced with underscore.
%%
%% This mimics Chronicle's scheme to that I don't get broken links.
title_to_filename(Title) ->
    F = fun(C) ->
		case lists:member(C, "ABCDEFGHIJKLMNOPQRSTUVWXZY"
				  "abcdefghijklmnopqrstuvwxyz"
				  "1234567890") of
		    true -> C;
		    false -> $_
		end
	end,
    lists:map(F, Title) ++ ".html".

parse_date(String) ->
    {ok, [Day, Monthname, Year], _} = io_lib:fread("~d. ~s ~d", String),
    {Year, monthname_to_month(Monthname), Day}.

monthname_to_month("January") -> 1;
monthname_to_month("February") -> 2;
monthname_to_month("March") -> 3;
monthname_to_month("April") -> 4;
monthname_to_month("May") -> 5;
monthname_to_month("June") -> 6;
monthname_to_month("July") -> 7;
monthname_to_month("August") -> 8;
monthname_to_month("September") -> 9;
monthname_to_month("October") -> 10;
monthname_to_month("November") -> 11;
monthname_to_month("December") -> 12.

tag_filename(Tag) ->
    "tagged_with_" ++ title_to_filename(Tag).

emit_tagged(Config, Articles) ->
    Tag_list = [Tags || #article{tags=Tags} <- Articles],
    Tags = lists:usort(lists:append(Tag_list)),
    lists:foreach(fun(Tag) -> emit_tagged(Config, Articles, Tag) end, Tags).

emit_tagged(Config, Articles, Tag) ->
    Relevant = articles_with_tag(Articles, Tag),
    Formatted_articles = lists:map(fun format_article/1, Relevant),

    Sidebar = html_div("sidebar", [about_box(Config),
				   toc(Relevant, "CATEGORY: " ++ Tag ),
				   categories(Articles)
				  ]),
    Articles_div = articles_div(Sidebar, Formatted_articles),
    Page = make_page(Config, Articles_div),

    ok = file:write_file(output_filename(Config, tag_filename(Tag)), Page).

emit_permalinks(Config, Articles) ->
    Sidebar = html_div("sidebar", [about_box(Config),
				   toc(Articles, "CATEGORY: All"),
				   categories(Articles)]),

    F = fun(Article) ->
		Formatted = format_article(Article),
		Page = make_page(Config, articles_div(Sidebar, [Formatted])),
		Filename = title_to_filename(Article#article.title),
		ok = file:write_file(output_filename(Config, Filename), Page)
	end,

    lists:foreach(F, Articles).

emit_first_page(Config, Articles) ->
    Formatted_articles = lists:map(fun format_article/1, Articles),

    Sidebar = html_div("sidebar", [about_box(Config),
				   toc(Articles, "CATEGORY: All"),
				   categories(Articles)]),
    Articles_div = articles_div(Sidebar, Formatted_articles),
    Page = make_page(Config, Articles_div),

    ok = file:write_file(output_filename(Config, "index.html"), Page).

output_filename(Config, Filename) ->
    {_, Path} = lists:keyfind(output, 1, Config),
    Path ++ "/" ++ Filename.

make_page(Config, Meat) ->
    {_, Title} = lists:keyfind(title, 1, Config),

    [header(),

     nltag("html",
	   [{"xmlns", "http://www.w3.org/1999/xhtml"},
	    {"xml:lang", "en"},
	    {"lang", "en"}],
	   [nltag("head",
		  [nltag("title", Title),
		   nltag("link", [{"rel", "stylesheet"},
				  {"type", "text/css"},
				  {"media", "screen"},
				  {"href", "./style.css"}], [])
		  ]),
	    nltag("body",
		  html_div("outer",
			   [masthead(Config), Meat, footer(Config)]
			  )
		 )
	   ])
     ].

format_article(#article{body = Body,
			date = Date,
			title = Title,
			tags = Tags,
			filename = Permalink}) ->
    Tag_links = [ html_a(tag_filename(Tag), Tag) || Tag <- Tags],
    Tag_line = tag("p", [html_a(Permalink, "Permalink"),
			 " | Tags: ",
			 string:join(Tag_links, ", ") ]),

    [nltag("h2", Title),
     nltag("p", [{"class", "posted"}],
	   tag("em", ["Posted ", format_date(Date)])),
     Body,
     tag("div", [{"class", "article-terminator"}], Tag_line)
    ].

format_date({Y, M, D}) ->
    Month = fun(N) -> element(N,
			      {"January", "February", "March", "April",
			       "May", "June", "July", "August",
			       "September", "October", "November", "December"})
	    end,
    Ord = fun(N) when N==1; N==21; N==31 -> "st";
	     (N) when N==2; N==22 -> "nd";
	     (N) when N==3; N==23 -> "rd";
	     (_) -> "th"
	  end,

    io_lib:fwrite("~s ~p~s ~p", [Month(M), D, Ord(D), Y]).

articles_div(Sidebar, Formatted_articles) ->
    html_div("articles", [Sidebar|Formatted_articles]).

header() ->
    ["<?xml version='1.0' encoding='utf-8'?>\n"
     "<!DOCTYPE html PUBLIC '-//W3C//DTD XHTML 1.0 Strict//EN'\n"
     "'http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd'>\n"].

masthead(Config) ->
    {_, Title} = lists:keyfind(title, 1, Config),
    {_, Subtitle} = lists:keyfind(subtitle, 1, Config),

    html_div("masthead", [html_a("index.html", Title),
			  "<br/>",
			  tag("span", [{"id", "subtitle"}], Subtitle)]).


footer(_Config) ->
    "".

about_box(Config) ->
    {_, About} = lists:keyfind(about, 1, Config),
    html_div("about",
	     [nltag("h3", "ABOUT"),
	      About]).

toc(Articles, Title) ->
    html_div("toc",
	     [nltag("h3", Title),
	      toc_entries(Articles)]).

toc_entries([]) -> [];
toc_entries(Articles) ->
    #article{date = {Y, _, _}} = hd(Articles),
    F = fun(#article{date = {Year, _, _}}) -> Year == Y end,
    {This, Rest} = lists:splitwith(F, Articles),
    [nltag("h4", integer_to_list(Y)),
     [lists:map(fun toc_entry/1, This), toc_entries(Rest)]].

toc_entry(#article{title=T, filename=F}) ->
    nltag("div", [{"class", "toc_entry"}], html_a(F, T)).

categories(Articles) ->
    Tag_list = [Tags || #article{tags=Tags} <- Articles],
    Tags = lists:usort(lists:append(Tag_list)),
    All = format_category_entry("index.html", "All articles", length(Articles)),
    Cats = lists:map(fun(Tag) -> category_entry(Articles, Tag) end, Tags),

    html_div("categories",
	     [nltag("h3", "CATEGORIES"), All, Cats]).

category_entry(Articles, Tag) ->
    N = length(articles_with_tag(Articles, Tag)),
    format_category_entry(tag_filename(Tag), Tag, N).

format_category_entry(Link, Tag, N) ->
    nltag("p", html_a(Link, Tag ++ "(" ++ integer_to_list(N) ++ ")")).

articles_with_tag(Articles, Tag) ->
    Filter = fun(#article{tags=Tags}) -> lists:member(Tag, Tags) end,
    lists:filter(Filter, Articles).

html_div(ID, Children) ->
    nltag("div", [{"id", ID}], Children).

html_a(Ref, Body) ->
    tag("a", [{"href", Ref}], Body).

nltag(Name, Children) ->
    nltag(Name, [], Children).

nltag(Name, Attributes, []) ->
    [tag(Name, Attributes, []), "\n"];

nltag(Name, Attributes, Children) ->
    ["<", Name, html_expand_attributes(Attributes), ">\n",
     Children, "</", Name, ">\n"].

tag(Name, Children) ->
    tag(Name, [], Children).

tag(Name, Attributes, []) ->
    ["<", Name, html_expand_attributes(Attributes), "/>"];

tag(Name, Attributes, Children) ->
    ["<", Name, html_expand_attributes(Attributes), ">",
     Children, "</", Name, ">"].

html_expand_attributes(List) ->
    F = fun({K, V}) -> [" ", K, "='", V, "'"] end,
    lists:map(F, List).
