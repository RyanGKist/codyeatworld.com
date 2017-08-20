module Jekyll
  module Tags
    class ExampleBlock < Liquid::Block
      include Liquid::StandardFilters

      LANGS = %w[html css js]

      def initialize(tag_name, markup, tokens)
        super
        @lang = markup.strip.downcase
        return if LANGS.include?(@lang)
        raise SyntaxError.new "Invalid syntax: '{% example #{markup} %}'. Expected: {% example <#{LANGS.join('|')}> %}."
      end

      def render(context)
        prefix = context["highlighter_prefix"] || ""
        suffix = context["highlighter_suffix"] || ""
        code = super.to_s.strip

        output = case context.registers[:site].highlighter

        when 'rouge'
          render_rouge(code)
        end

        rendered_output = example(code) + add_code_tag(output)
        prefix + rendered_output + suffix
      end

      def example(output)
        "<div class=\"sombra-example\">\n#{output}\n</div>"
      end

      def render_rouge(code)
        require 'rouge'
        formatter = Rouge::Formatters::HTML.new(line_numbers: false, wrap: false)
        lexer = Rouge::Lexer.find_fancy(@lang, code) || Rouge::Lexers::PlainText
        code = formatter.format(lexer.lex(code))
        "<div class=\"highlight\"><pre>#{code}</pre></div>"
      end

      def add_code_tag(code)
        # Add nested <code> tags to code blocks
        code = code.sub(/<pre>\n*/,'<pre><code class="language-' + @lang.to_s.gsub("+", "-") + '" data-lang="' + @lang.to_s + '">')
        code = code.sub(/\n*<\/pre>/,"</code></pre>")
        code.strip
      end

    end
  end
end

Liquid::Template.register_tag('example', Jekyll::Tags::ExampleBlock)
