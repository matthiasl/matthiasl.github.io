root_dir_files=style.css

all: validate output/index.html

output/index.html: src/*.html make_blog.beam config output
	erl -noinput -s make_blog go

# This rule validates the _input_ HTML. That catches HTML errors
# in the code I write. See also validation in 'publish'
validate: $(patsubst %.html, %.valid, $(wildcard src/*.html))

output:
	mkdir output

src/%.valid: src/%.html
	./format_single_page $< | xmllint --valid --noout --nonet - > $@

%.beam: %.erl
	erlc $<

# Validate the _output_ HTML and copy to the live site. The validation
# catches errors introduced by the Erlang blog software
publish:
	xmllint --valid --noout --nonet output/*html
	scp -r output/* baco_root:/home/yaws/blog/

clean:
	rm -rf output/*
	rm -f src/*.valid
