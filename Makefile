root_dir_files=style.css

all: validate output/index.html
	cp img/* output/

output/index.html: src/*.html make_blog.beam config output output/style.css
	erl -noinput -s make_blog go

output/style.css: style.css
	cp $< $@

# This rule validates the _input_ HTML. That catches HTML errors
# in the code I write. See also validation in 'publish'
validate: $(patsubst %.html, %.valid, $(wildcard src/*.html))

output:
	mkdir output

src/%.valid: src/%.html
	./format_single_page $< | xmllint --valid --noout --nonet - > $@

%.beam: %.erl
	erlc $<

# Validate the _output_ HTML.
publish:
	xmllint --valid --noout --nonet output/*html
	@echo "To publish, commit the files in 'output' and push to upstream (github)"

clean:
	rm -rf output/*
	rm -f src/*.valid
