class Atomy::Parser
  # :stopdoc:

    # This is distinct from setup_parser so that a standalone parser
    # can redefine #initialize and still have access to the proper
    # parser setup code.
    def initialize(str, debug=false)
      setup_parser(str, debug)
    end



    # Prepares for parsing +str+.  If you define a custom initialize you must
    # call this method before #parse
    def setup_parser(str, debug=false)
      @string = str
      @pos = 0
      @memoizations = Hash.new { |h,k| h[k] = {} }
      @result = nil
      @failed_rule = nil
      @failing_rule_offset = -1

      setup_foreign_grammar
    end

    attr_reader :string
    attr_reader :failing_rule_offset
    attr_accessor :result, :pos

    
    def current_column(target=pos)
      if c = string.rindex("\n", target-1)
        return target - c - 1
      end

      target + 1
    end

    def current_line(target=pos)
      cur_offset = 0
      cur_line = 0

      string.each_line do |line|
        cur_line += 1
        cur_offset += line.size
        return cur_line if cur_offset >= target
      end

      -1
    end

    def lines
      lines = []
      string.each_line { |l| lines << l }
      lines
    end



    def get_text(start)
      @string[start..@pos-1]
    end

    def show_pos
      width = 10
      if @pos < width
        "#{@pos} (\"#{@string[0,@pos]}\" @ \"#{@string[@pos,width]}\")"
      else
        "#{@pos} (\"... #{@string[@pos - width, width]}\" @ \"#{@string[@pos,width]}\")"
      end
    end

    def failure_info
      l = current_line @failing_rule_offset
      c = current_column @failing_rule_offset

      if @failed_rule.kind_of? Symbol
        info = self.class::Rules[@failed_rule]
        "line #{l}, column #{c}: failed rule '#{info.name}' = '#{info.rendered}'"
      else
        "line #{l}, column #{c}: failed rule '#{@failed_rule}'"
      end
    end

    def failure_caret
      l = current_line @failing_rule_offset
      c = current_column @failing_rule_offset

      line = lines[l-1]
      "#{line}\n#{' ' * (c - 1)}^"
    end

    def failure_character
      l = current_line @failing_rule_offset
      c = current_column @failing_rule_offset
      lines[l-1][c-1, 1]
    end

    def failure_oneline
      l = current_line @failing_rule_offset
      c = current_column @failing_rule_offset

      char = lines[l-1][c-1, 1]

      if @failed_rule.kind_of? Symbol
        info = self.class::Rules[@failed_rule]
        "@#{l}:#{c} failed rule '#{info.name}', got '#{char}'"
      else
        "@#{l}:#{c} failed rule '#{@failed_rule}', got '#{char}'"
      end
    end

    class ParseError < RuntimeError
    end

    def raise_error
      raise ParseError, failure_oneline
    end

    def show_error(io=STDOUT)
      error_pos = @failing_rule_offset
      line_no = current_line(error_pos)
      col_no = current_column(error_pos)

      io.puts "On line #{line_no}, column #{col_no}:"

      if @failed_rule.kind_of? Symbol
        info = self.class::Rules[@failed_rule]
        io.puts "Failed to match '#{info.rendered}' (rule '#{info.name}')"
      else
        io.puts "Failed to match rule '#{@failed_rule}'"
      end

      io.puts "Got: #{string[error_pos,1].inspect}"
      line = lines[line_no-1]
      io.puts "=> #{line}"
      io.print(" " * (col_no + 3))
      io.puts "^"
    end

    def set_failed_rule(name)
      if @pos > @failing_rule_offset
        @failed_rule = name
        @failing_rule_offset = @pos
      end
    end

    attr_reader :failed_rule

    def match_string(str)
      len = str.size
      if @string[pos,len] == str
        @pos += len
        return str
      end

      return nil
    end

    def scan(reg)
      if m = reg.match(@string[@pos..-1])
        width = m.end(0)
        @pos += width
        return true
      end

      return nil
    end

    if "".respond_to? :getbyte
      def get_byte
        if @pos >= @string.size
          return nil
        end

        s = @string.getbyte @pos
        @pos += 1
        s
      end
    else
      def get_byte
        if @pos >= @string.size
          return nil
        end

        s = @string[@pos]
        @pos += 1
        s
      end
    end

    def parse(rule=nil)
      # We invoke the rules indirectly via apply
      # instead of by just calling them as methods because
      # if the rules use left recursion, apply needs to
      # manage that.

      if !rule
        apply(:_root)
      else
        method = rule.gsub("-","_hyphen_")
        apply :"_#{method}"
      end
    end

    class MemoEntry
      def initialize(ans, pos)
        @ans = ans
        @pos = pos
        @result = nil
        @set = false
        @left_rec = false
      end

      attr_reader :ans, :pos, :result, :set
      attr_accessor :left_rec

      def move!(ans, pos, result)
        @ans = ans
        @pos = pos
        @result = result
        @set = true
        @left_rec = false
      end
    end

    def external_invoke(other, rule, *args)
      old_pos = @pos
      old_string = @string

      @pos = other.pos
      @string = other.string

      begin
        if val = __send__(rule, *args)
          other.pos = @pos
          other.result = @result
        else
          other.set_failed_rule "#{self.class}##{rule}"
        end
        val
      ensure
        @pos = old_pos
        @string = old_string
      end
    end

    def apply_with_args(rule, *args)
      memo_key = [rule, args]
      if m = @memoizations[memo_key][@pos]
        @pos = m.pos
        if !m.set
          m.left_rec = true
          return nil
        end

        @result = m.result

        return m.ans
      else
        m = MemoEntry.new(nil, @pos)
        @memoizations[memo_key][@pos] = m
        start_pos = @pos

        ans = __send__ rule, *args

        lr = m.left_rec

        m.move! ans, @pos, @result

        # Don't bother trying to grow the left recursion
        # if it's failing straight away (thus there is no seed)
        if ans and lr
          return grow_lr(rule, args, start_pos, m)
        else
          return ans
        end

        return ans
      end
    end

    def apply(rule)
      if m = @memoizations[rule][@pos]
        @pos = m.pos
        if !m.set
          m.left_rec = true
          return nil
        end

        @result = m.result

        return m.ans
      else
        m = MemoEntry.new(nil, @pos)
        @memoizations[rule][@pos] = m
        start_pos = @pos

        ans = __send__ rule

        lr = m.left_rec

        m.move! ans, @pos, @result

        # Don't bother trying to grow the left recursion
        # if it's failing straight away (thus there is no seed)
        if ans and lr
          return grow_lr(rule, nil, start_pos, m)
        else
          return ans
        end

        return ans
      end
    end

    def grow_lr(rule, args, start_pos, m)
      while true
        @pos = start_pos
        @result = m.result

        if args
          ans = __send__ rule, *args
        else
          ans = __send__ rule
        end
        return nil unless ans

        break if @pos <= m.pos

        m.move! ans, @pos, @result
      end

      @result = m.result
      @pos = m.pos
      return m.ans
    end

    class RuleInfo
      def initialize(name, rendered)
        @name = name
        @rendered = rendered
      end

      attr_reader :name, :rendered
    end

    def self.rule_info(name, rendered)
      RuleInfo.new(name, rendered)
    end


  # :startdoc:
  # :stopdoc:
  def setup_foreign_grammar; end

  # sp = (" " | "\t" | comment)*
  def _sp
    while true

      _save1 = self.pos
      while true # choice
        _tmp = match_string(" ")
        break if _tmp
        self.pos = _save1
        _tmp = match_string("\t")
        break if _tmp
        self.pos = _save1
        _tmp = apply(:_comment)
        break if _tmp
        self.pos = _save1
        break
      end # end choice

      break unless _tmp
    end
    _tmp = true
    set_failed_rule :_sp unless _tmp
    return _tmp
  end

  # wsp = (" " | "\t" | "\n" | comment)*
  def _wsp
    while true

      _save1 = self.pos
      while true # choice
        _tmp = match_string(" ")
        break if _tmp
        self.pos = _save1
        _tmp = match_string("\t")
        break if _tmp
        self.pos = _save1
        _tmp = match_string("\n")
        break if _tmp
        self.pos = _save1
        _tmp = apply(:_comment)
        break if _tmp
        self.pos = _save1
        break
      end # end choice

      break unless _tmp
    end
    _tmp = true
    set_failed_rule :_wsp unless _tmp
    return _tmp
  end

  # sig_sp = (" " | "\t" | comment)+
  def _sig_sp
    _save = self.pos

    _save1 = self.pos
    while true # choice
      _tmp = match_string(" ")
      break if _tmp
      self.pos = _save1
      _tmp = match_string("\t")
      break if _tmp
      self.pos = _save1
      _tmp = apply(:_comment)
      break if _tmp
      self.pos = _save1
      break
    end # end choice

    if _tmp
      while true

        _save2 = self.pos
        while true # choice
          _tmp = match_string(" ")
          break if _tmp
          self.pos = _save2
          _tmp = match_string("\t")
          break if _tmp
          self.pos = _save2
          _tmp = apply(:_comment)
          break if _tmp
          self.pos = _save2
          break
        end # end choice

        break unless _tmp
      end
      _tmp = true
    else
      self.pos = _save
    end
    set_failed_rule :_sig_sp unless _tmp
    return _tmp
  end

  # sig_wsp = (" " | "\t" | "\n" | comment)+
  def _sig_wsp
    _save = self.pos

    _save1 = self.pos
    while true # choice
      _tmp = match_string(" ")
      break if _tmp
      self.pos = _save1
      _tmp = match_string("\t")
      break if _tmp
      self.pos = _save1
      _tmp = match_string("\n")
      break if _tmp
      self.pos = _save1
      _tmp = apply(:_comment)
      break if _tmp
      self.pos = _save1
      break
    end # end choice

    if _tmp
      while true

        _save2 = self.pos
        while true # choice
          _tmp = match_string(" ")
          break if _tmp
          self.pos = _save2
          _tmp = match_string("\t")
          break if _tmp
          self.pos = _save2
          _tmp = match_string("\n")
          break if _tmp
          self.pos = _save2
          _tmp = apply(:_comment)
          break if _tmp
          self.pos = _save2
          break
        end # end choice

        break unless _tmp
      end
      _tmp = true
    else
      self.pos = _save
    end
    set_failed_rule :_sig_wsp unless _tmp
    return _tmp
  end

  # shebang = "#!" /.*?$/
  def _shebang

    _save = self.pos
    while true # sequence
      _tmp = match_string("#!")
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = scan(/\A(?-mix:.*?$)/)
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_shebang unless _tmp
    return _tmp
  end

  # cont = (("\n" sp)+ &{ continue?(p) } | sig_sp cont(p)? | !"(")
  def _cont(p)

    _save = self.pos
    while true # choice

      _save1 = self.pos
      while true # sequence
        _save2 = self.pos

        _save3 = self.pos
        while true # sequence
          _tmp = match_string("\n")
          unless _tmp
            self.pos = _save3
            break
          end
          _tmp = apply(:_sp)
          unless _tmp
            self.pos = _save3
          end
          break
        end # end sequence

        if _tmp
          while true

            _save4 = self.pos
            while true # sequence
              _tmp = match_string("\n")
              unless _tmp
                self.pos = _save4
                break
              end
              _tmp = apply(:_sp)
              unless _tmp
                self.pos = _save4
              end
              break
            end # end sequence

            break unless _tmp
          end
          _tmp = true
        else
          self.pos = _save2
        end
        unless _tmp
          self.pos = _save1
          break
        end
        _save5 = self.pos
        _tmp = begin;  continue?(p) ; end
        self.pos = _save5
        unless _tmp
          self.pos = _save1
        end
        break
      end # end sequence

      break if _tmp
      self.pos = _save

      _save6 = self.pos
      while true # sequence
        _tmp = apply(:_sig_sp)
        unless _tmp
          self.pos = _save6
          break
        end
        _save7 = self.pos
        _tmp = apply_with_args(:_cont, p)
        unless _tmp
          _tmp = true
          self.pos = _save7
        end
        unless _tmp
          self.pos = _save6
        end
        break
      end # end sequence

      break if _tmp
      self.pos = _save
      _save8 = self.pos
      _tmp = match_string("(")
      _tmp = _tmp ? nil : true
      self.pos = _save8
      break if _tmp
      self.pos = _save
      break
    end # end choice

    set_failed_rule :_cont unless _tmp
    return _tmp
  end

  # line = { current_line }
  def _line
    @result = begin;  current_line ; end
    _tmp = true
    set_failed_rule :_line unless _tmp
    return _tmp
  end

  # op_letter = !"`" < /[\p{S}!@#%&*\-\\.\/\?]/u > { text.to_sym }
  def _op_letter

    _save = self.pos
    while true # sequence
      _save1 = self.pos
      _tmp = match_string("`")
      _tmp = _tmp ? nil : true
      self.pos = _save1
      unless _tmp
        self.pos = _save
        break
      end
      _text_start = self.pos
      _tmp = scan(/\A(?-mix:[\p{S}!@#%&*\-\\.\/\?])/u)
      if _tmp
        text = get_text(_text_start)
      end
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  text.to_sym ; end
      _tmp = true
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_op_letter unless _tmp
    return _tmp
  end

  # operator = < !"~" ":"? op_letter+ > { text.to_sym }
  def _operator

    _save = self.pos
    while true # sequence
      _text_start = self.pos

      _save1 = self.pos
      while true # sequence
        _save2 = self.pos
        _tmp = match_string("~")
        _tmp = _tmp ? nil : true
        self.pos = _save2
        unless _tmp
          self.pos = _save1
          break
        end
        _save3 = self.pos
        _tmp = match_string(":")
        unless _tmp
          _tmp = true
          self.pos = _save3
        end
        unless _tmp
          self.pos = _save1
          break
        end
        _save4 = self.pos
        _tmp = apply(:_op_letter)
        if _tmp
          while true
            _tmp = apply(:_op_letter)
            break unless _tmp
          end
          _tmp = true
        else
          self.pos = _save4
        end
        unless _tmp
          self.pos = _save1
        end
        break
      end # end sequence

      if _tmp
        text = get_text(_text_start)
      end
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  text.to_sym ; end
      _tmp = true
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_operator unless _tmp
    return _tmp
  end

  # identifier = < /[\p{Ll}_][\p{L}\d\-_]*/u > { text.tr("-", "_").to_sym }
  def _identifier

    _save = self.pos
    while true # sequence
      _text_start = self.pos
      _tmp = scan(/\A(?-mix:[\p{Ll}_][\p{L}\d\-_]*)/u)
      if _tmp
        text = get_text(_text_start)
      end
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  text.tr("-", "_").to_sym ; end
      _tmp = true
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_identifier unless _tmp
    return _tmp
  end

  # grouped = "(" wsp expression:x wsp ")" { x }
  def _grouped

    _save = self.pos
    while true # sequence
      _tmp = match_string("(")
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_wsp)
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_expression)
      x = @result
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_wsp)
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string(")")
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  x ; end
      _tmp = true
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_grouped unless _tmp
    return _tmp
  end

  # comment = (/--.*?$/ | multi_comment)
  def _comment

    _save = self.pos
    while true # choice
      _tmp = scan(/\A(?-mix:--.*?$)/)
      break if _tmp
      self.pos = _save
      _tmp = apply(:_multi_comment)
      break if _tmp
      self.pos = _save
      break
    end # end choice

    set_failed_rule :_comment unless _tmp
    return _tmp
  end

  # multi_comment = "{-" in_multi
  def _multi_comment

    _save = self.pos
    while true # sequence
      _tmp = match_string("{-")
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_in_multi)
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_multi_comment unless _tmp
    return _tmp
  end

  # in_multi = (/[^\-\{\}]*/ "-}" | /[^\-\{\}]*/ "{-" in_multi /[^\-\{\}]*/ "-}" | /[^\-\{\}]*/ /[-{}]/ in_multi)
  def _in_multi

    _save = self.pos
    while true # choice

      _save1 = self.pos
      while true # sequence
        _tmp = scan(/\A(?-mix:[^\-\{\}]*)/)
        unless _tmp
          self.pos = _save1
          break
        end
        _tmp = match_string("-}")
        unless _tmp
          self.pos = _save1
        end
        break
      end # end sequence

      break if _tmp
      self.pos = _save

      _save2 = self.pos
      while true # sequence
        _tmp = scan(/\A(?-mix:[^\-\{\}]*)/)
        unless _tmp
          self.pos = _save2
          break
        end
        _tmp = match_string("{-")
        unless _tmp
          self.pos = _save2
          break
        end
        _tmp = apply(:_in_multi)
        unless _tmp
          self.pos = _save2
          break
        end
        _tmp = scan(/\A(?-mix:[^\-\{\}]*)/)
        unless _tmp
          self.pos = _save2
          break
        end
        _tmp = match_string("-}")
        unless _tmp
          self.pos = _save2
        end
        break
      end # end sequence

      break if _tmp
      self.pos = _save

      _save3 = self.pos
      while true # sequence
        _tmp = scan(/\A(?-mix:[^\-\{\}]*)/)
        unless _tmp
          self.pos = _save3
          break
        end
        _tmp = scan(/\A(?-mix:[-{}])/)
        unless _tmp
          self.pos = _save3
          break
        end
        _tmp = apply(:_in_multi)
        unless _tmp
          self.pos = _save3
        end
        break
      end # end sequence

      break if _tmp
      self.pos = _save
      break
    end # end choice

    set_failed_rule :_in_multi unless _tmp
    return _tmp
  end

  # delim = (wsp "," wsp | (sp "\n" sp)+ &{ current_column >= c })
  def _delim(c)

    _save = self.pos
    while true # choice

      _save1 = self.pos
      while true # sequence
        _tmp = apply(:_wsp)
        unless _tmp
          self.pos = _save1
          break
        end
        _tmp = match_string(",")
        unless _tmp
          self.pos = _save1
          break
        end
        _tmp = apply(:_wsp)
        unless _tmp
          self.pos = _save1
        end
        break
      end # end sequence

      break if _tmp
      self.pos = _save

      _save2 = self.pos
      while true # sequence
        _save3 = self.pos

        _save4 = self.pos
        while true # sequence
          _tmp = apply(:_sp)
          unless _tmp
            self.pos = _save4
            break
          end
          _tmp = match_string("\n")
          unless _tmp
            self.pos = _save4
            break
          end
          _tmp = apply(:_sp)
          unless _tmp
            self.pos = _save4
          end
          break
        end # end sequence

        if _tmp
          while true

            _save5 = self.pos
            while true # sequence
              _tmp = apply(:_sp)
              unless _tmp
                self.pos = _save5
                break
              end
              _tmp = match_string("\n")
              unless _tmp
                self.pos = _save5
                break
              end
              _tmp = apply(:_sp)
              unless _tmp
                self.pos = _save5
              end
              break
            end # end sequence

            break unless _tmp
          end
          _tmp = true
        else
          self.pos = _save3
        end
        unless _tmp
          self.pos = _save2
          break
        end
        _save6 = self.pos
        _tmp = begin;  current_column >= c ; end
        self.pos = _save6
        unless _tmp
          self.pos = _save2
        end
        break
      end # end sequence

      break if _tmp
      self.pos = _save
      break
    end # end choice

    set_failed_rule :_delim unless _tmp
    return _tmp
  end

  # expression = level4
  def _expression
    _tmp = apply(:_level4)
    set_failed_rule :_expression unless _tmp
    return _tmp
  end

  # one_expression = wsp expression:e wsp !. { e }
  def _one_expression

    _save = self.pos
    while true # sequence
      _tmp = apply(:_wsp)
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_expression)
      e = @result
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_wsp)
      unless _tmp
        self.pos = _save
        break
      end
      _save1 = self.pos
      _tmp = get_byte
      _tmp = _tmp ? nil : true
      self.pos = _save1
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  e ; end
      _tmp = true
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_one_expression unless _tmp
    return _tmp
  end

  # expressions = { current_column }:c expression:x (delim(c) expression)*:xs { [x] + Array(xs) }
  def _expressions

    _save = self.pos
    while true # sequence
      @result = begin;  current_column ; end
      _tmp = true
      c = @result
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_expression)
      x = @result
      unless _tmp
        self.pos = _save
        break
      end
      _ary = []
      while true

        _save2 = self.pos
        while true # sequence
          _tmp = apply_with_args(:_delim, c)
          unless _tmp
            self.pos = _save2
            break
          end
          _tmp = apply(:_expression)
          unless _tmp
            self.pos = _save2
          end
          break
        end # end sequence

        _ary << @result if _tmp
        break unless _tmp
      end
      _tmp = true
      @result = _ary
      xs = @result
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  [x] + Array(xs) ; end
      _tmp = true
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_expressions unless _tmp
    return _tmp
  end

  # level0 = (number | quote | quasi_quote | unquote | string | constant | word(no_op) | block | list | prefix)
  def _level0(no_op)

    _save = self.pos
    while true # choice
      _tmp = apply(:_number)
      break if _tmp
      self.pos = _save
      _tmp = apply(:_quote)
      break if _tmp
      self.pos = _save
      _tmp = apply(:_quasi_quote)
      break if _tmp
      self.pos = _save
      _tmp = apply(:_unquote)
      break if _tmp
      self.pos = _save
      _tmp = apply(:_string)
      break if _tmp
      self.pos = _save
      _tmp = apply(:_constant)
      break if _tmp
      self.pos = _save
      _tmp = apply_with_args(:_word, no_op)
      break if _tmp
      self.pos = _save
      _tmp = apply(:_block)
      break if _tmp
      self.pos = _save
      _tmp = apply(:_list)
      break if _tmp
      self.pos = _save
      _tmp = apply(:_prefix)
      break if _tmp
      self.pos = _save
      break
    end # end choice

    set_failed_rule :_level0 unless _tmp
    return _tmp
  end

  # level1 = (call | grouped | level0(true))
  def _level1

    _save = self.pos
    while true # choice
      _tmp = apply(:_call)
      break if _tmp
      self.pos = _save
      _tmp = apply(:_grouped)
      break if _tmp
      self.pos = _save
      _tmp = apply_with_args(:_level0, true)
      break if _tmp
      self.pos = _save
      break
    end # end choice

    set_failed_rule :_level1 unless _tmp
    return _tmp
  end

  # level2 = (postfix | level1)
  def _level2

    _save = self.pos
    while true # choice
      _tmp = apply(:_postfix)
      break if _tmp
      self.pos = _save
      _tmp = apply(:_level1)
      break if _tmp
      self.pos = _save
      break
    end # end choice

    set_failed_rule :_level2 unless _tmp
    return _tmp
  end

  # level3 = (compose | level2)
  def _level3

    _save = self.pos
    while true # choice
      _tmp = apply(:_compose)
      break if _tmp
      self.pos = _save
      _tmp = apply(:_level2)
      break if _tmp
      self.pos = _save
      break
    end # end choice

    set_failed_rule :_level3 unless _tmp
    return _tmp
  end

  # level4 = (language | infix | level3)
  def _level4

    _save = self.pos
    while true # choice
      _tmp = apply(:_language)
      break if _tmp
      self.pos = _save
      _tmp = apply(:_infix)
      break if _tmp
      self.pos = _save
      _tmp = apply(:_level3)
      break if _tmp
      self.pos = _save
      break
    end # end choice

    set_failed_rule :_level4 unless _tmp
    return _tmp
  end

  # number = (line:line < /[\+\-]?0[oO][0-7]+/ > { create(Primitive, line, :value => text.to_i(8)) } | line:line < /[\+\-]?0[xX][\da-fA-F]+/ > { create(Primitive, line, :value => text.to_i(16)) } | line:line < /[\+\-]?\d+(\.\d+)?[eE][\+\-]?\d+/ > { create(Literal, line, :value => text.to_f) } | line:line < /[\+\-]?\d+\.\d+/ > { create(Literal, line, :value => text.to_f) } | line:line < /[\+\-]?\d+/ > { create(Primitive, line, :value => text.to_i) })
  def _number

    _save = self.pos
    while true # choice

      _save1 = self.pos
      while true # sequence
        _tmp = apply(:_line)
        line = @result
        unless _tmp
          self.pos = _save1
          break
        end
        _text_start = self.pos
        _tmp = scan(/\A(?-mix:[\+\-]?0[oO][0-7]+)/)
        if _tmp
          text = get_text(_text_start)
        end
        unless _tmp
          self.pos = _save1
          break
        end
        @result = begin;  create(Primitive, line, :value => text.to_i(8)) ; end
        _tmp = true
        unless _tmp
          self.pos = _save1
        end
        break
      end # end sequence

      break if _tmp
      self.pos = _save

      _save2 = self.pos
      while true # sequence
        _tmp = apply(:_line)
        line = @result
        unless _tmp
          self.pos = _save2
          break
        end
        _text_start = self.pos
        _tmp = scan(/\A(?-mix:[\+\-]?0[xX][\da-fA-F]+)/)
        if _tmp
          text = get_text(_text_start)
        end
        unless _tmp
          self.pos = _save2
          break
        end
        @result = begin;  create(Primitive, line, :value => text.to_i(16)) ; end
        _tmp = true
        unless _tmp
          self.pos = _save2
        end
        break
      end # end sequence

      break if _tmp
      self.pos = _save

      _save3 = self.pos
      while true # sequence
        _tmp = apply(:_line)
        line = @result
        unless _tmp
          self.pos = _save3
          break
        end
        _text_start = self.pos
        _tmp = scan(/\A(?-mix:[\+\-]?\d+(\.\d+)?[eE][\+\-]?\d+)/)
        if _tmp
          text = get_text(_text_start)
        end
        unless _tmp
          self.pos = _save3
          break
        end
        @result = begin;  create(Literal, line, :value => text.to_f) ; end
        _tmp = true
        unless _tmp
          self.pos = _save3
        end
        break
      end # end sequence

      break if _tmp
      self.pos = _save

      _save4 = self.pos
      while true # sequence
        _tmp = apply(:_line)
        line = @result
        unless _tmp
          self.pos = _save4
          break
        end
        _text_start = self.pos
        _tmp = scan(/\A(?-mix:[\+\-]?\d+\.\d+)/)
        if _tmp
          text = get_text(_text_start)
        end
        unless _tmp
          self.pos = _save4
          break
        end
        @result = begin;  create(Literal, line, :value => text.to_f) ; end
        _tmp = true
        unless _tmp
          self.pos = _save4
        end
        break
      end # end sequence

      break if _tmp
      self.pos = _save

      _save5 = self.pos
      while true # sequence
        _tmp = apply(:_line)
        line = @result
        unless _tmp
          self.pos = _save5
          break
        end
        _text_start = self.pos
        _tmp = scan(/\A(?-mix:[\+\-]?\d+)/)
        if _tmp
          text = get_text(_text_start)
        end
        unless _tmp
          self.pos = _save5
          break
        end
        @result = begin;  create(Primitive, line, :value => text.to_i) ; end
        _tmp = true
        unless _tmp
          self.pos = _save5
        end
        break
      end # end sequence

      break if _tmp
      self.pos = _save
      break
    end # end choice

    set_failed_rule :_number unless _tmp
    return _tmp
  end

  # language = "#language" wsp identifier:n { set_lang(n) } %lang.root
  def _language

    _save = self.pos
    while true # sequence
      _tmp = match_string("#language")
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_wsp)
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_identifier)
      n = @result
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  set_lang(n) ; end
      _tmp = true
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = @_grammar_lang.external_invoke(self, :_root)
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_language unless _tmp
    return _tmp
  end

  # quote = line:line "'" level2:e { create(Quote, line, :expression => e) }
  def _quote

    _save = self.pos
    while true # sequence
      _tmp = apply(:_line)
      line = @result
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string("'")
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_level2)
      e = @result
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  create(Quote, line, :expression => e) ; end
      _tmp = true
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_quote unless _tmp
    return _tmp
  end

  # quasi_quote = line:line "`" level2:e { create(QuasiQuote, line, :expression => e) }
  def _quasi_quote

    _save = self.pos
    while true # sequence
      _tmp = apply(:_line)
      line = @result
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string("`")
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_level2)
      e = @result
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  create(QuasiQuote, line, :expression => e) ; end
      _tmp = true
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_quasi_quote unless _tmp
    return _tmp
  end

  # unquote = line:line "~" level2:e { create(Unquote, line, :expression => e) }
  def _unquote

    _save = self.pos
    while true # sequence
      _tmp = apply(:_line)
      line = @result
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string("~")
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_level2)
      e = @result
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  create(Unquote, line, :expression => e) ; end
      _tmp = true
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_unquote unless _tmp
    return _tmp
  end

  # escape = (number_escapes | escapes)
  def _escape

    _save = self.pos
    while true # choice
      _tmp = apply(:_number_escapes)
      break if _tmp
      self.pos = _save
      _tmp = apply(:_escapes)
      break if _tmp
      self.pos = _save
      break
    end # end choice

    set_failed_rule :_escape unless _tmp
    return _tmp
  end

  # str_seq = < /[^\\"]+/ > { text }
  def _str_seq

    _save = self.pos
    while true # sequence
      _text_start = self.pos
      _tmp = scan(/\A(?-mix:[^\\"]+)/)
      if _tmp
        text = get_text(_text_start)
      end
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  text ; end
      _tmp = true
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_str_seq unless _tmp
    return _tmp
  end

  # string = line:line "\"" < ("\\" escape | str_seq)*:c > "\"" { create(StringLiteral, line,                         :value => c.join,                         :raw => text.gsub("\\\"", "\""))                     }
  def _string

    _save = self.pos
    while true # sequence
      _tmp = apply(:_line)
      line = @result
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string("\"")
      unless _tmp
        self.pos = _save
        break
      end
      _text_start = self.pos
      _ary = []
      while true

        _save2 = self.pos
        while true # choice

          _save3 = self.pos
          while true # sequence
            _tmp = match_string("\\")
            unless _tmp
              self.pos = _save3
              break
            end
            _tmp = apply(:_escape)
            unless _tmp
              self.pos = _save3
            end
            break
          end # end sequence

          break if _tmp
          self.pos = _save2
          _tmp = apply(:_str_seq)
          break if _tmp
          self.pos = _save2
          break
        end # end choice

        _ary << @result if _tmp
        break unless _tmp
      end
      _tmp = true
      @result = _ary
      c = @result
      if _tmp
        text = get_text(_text_start)
      end
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string("\"")
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  create(StringLiteral, line,
                        :value => c.join,
                        :raw => text.gsub("\\\"", "\""))
                    ; end
      _tmp = true
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_string unless _tmp
    return _tmp
  end

  # constant_name = < /[A-Z][a-zA-Z0-9_]*/ > { text.to_sym }
  def _constant_name

    _save = self.pos
    while true # sequence
      _text_start = self.pos
      _tmp = scan(/\A(?-mix:[A-Z][a-zA-Z0-9_]*)/)
      if _tmp
        text = get_text(_text_start)
      end
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  text.to_sym ; end
      _tmp = true
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_constant_name unless _tmp
    return _tmp
  end

  # constant = line:line constant_name:n { create(Constant, line, :name => n) }
  def _constant

    _save = self.pos
    while true # sequence
      _tmp = apply(:_line)
      line = @result
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_constant_name)
      n = @result
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  create(Constant, line, :name => n) ; end
      _tmp = true
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_constant unless _tmp
    return _tmp
  end

  # word = line:line identifier:n !{ no_op && operator?(n) } { create(Word, line, :text => n) }
  def _word(no_op)

    _save = self.pos
    while true # sequence
      _tmp = apply(:_line)
      line = @result
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_identifier)
      n = @result
      unless _tmp
        self.pos = _save
        break
      end
      _save1 = self.pos
      _tmp = begin;  no_op && operator?(n) ; end
      _tmp = _tmp ? nil : true
      self.pos = _save1
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  create(Word, line, :text => n) ; end
      _tmp = true
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_word unless _tmp
    return _tmp
  end

  # prefix = line:line op_letter:o level2:e { create(Prefix, line, :receiver => e, :operator => o) }
  def _prefix

    _save = self.pos
    while true # sequence
      _tmp = apply(:_line)
      line = @result
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_op_letter)
      o = @result
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_level2)
      e = @result
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  create(Prefix, line, :receiver => e, :operator => o) ; end
      _tmp = true
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_prefix unless _tmp
    return _tmp
  end

  # postfix = (line:line postfix:e op_letter:o { create(Postfix, line, :receiver => e, :operator => o) } | line:line level1:e op_letter:o { create(Postfix, line, :receiver => e, :operator => o) })
  def _postfix

    _save = self.pos
    while true # choice

      _save1 = self.pos
      while true # sequence
        _tmp = apply(:_line)
        line = @result
        unless _tmp
          self.pos = _save1
          break
        end
        _tmp = apply(:_postfix)
        e = @result
        unless _tmp
          self.pos = _save1
          break
        end
        _tmp = apply(:_op_letter)
        o = @result
        unless _tmp
          self.pos = _save1
          break
        end
        @result = begin;  create(Postfix, line, :receiver => e, :operator => o) ; end
        _tmp = true
        unless _tmp
          self.pos = _save1
        end
        break
      end # end sequence

      break if _tmp
      self.pos = _save

      _save2 = self.pos
      while true # sequence
        _tmp = apply(:_line)
        line = @result
        unless _tmp
          self.pos = _save2
          break
        end
        _tmp = apply(:_level1)
        e = @result
        unless _tmp
          self.pos = _save2
          break
        end
        _tmp = apply(:_op_letter)
        o = @result
        unless _tmp
          self.pos = _save2
          break
        end
        @result = begin;  create(Postfix, line, :receiver => e, :operator => o) ; end
        _tmp = true
        unless _tmp
          self.pos = _save2
        end
        break
      end # end sequence

      break if _tmp
      self.pos = _save
      break
    end # end choice

    set_failed_rule :_postfix unless _tmp
    return _tmp
  end

  # block = (line:line ":" !op_letter wsp expressions?:es (wsp ";")? { create(Block, line, :contents => Array(es)) } | line:line "{" wsp expressions?:es wsp "}" { create(Block, line, :contents => Array(es)) })
  def _block

    _save = self.pos
    while true # choice

      _save1 = self.pos
      while true # sequence
        _tmp = apply(:_line)
        line = @result
        unless _tmp
          self.pos = _save1
          break
        end
        _tmp = match_string(":")
        unless _tmp
          self.pos = _save1
          break
        end
        _save2 = self.pos
        _tmp = apply(:_op_letter)
        _tmp = _tmp ? nil : true
        self.pos = _save2
        unless _tmp
          self.pos = _save1
          break
        end
        _tmp = apply(:_wsp)
        unless _tmp
          self.pos = _save1
          break
        end
        _save3 = self.pos
        _tmp = apply(:_expressions)
        @result = nil unless _tmp
        unless _tmp
          _tmp = true
          self.pos = _save3
        end
        es = @result
        unless _tmp
          self.pos = _save1
          break
        end
        _save4 = self.pos

        _save5 = self.pos
        while true # sequence
          _tmp = apply(:_wsp)
          unless _tmp
            self.pos = _save5
            break
          end
          _tmp = match_string(";")
          unless _tmp
            self.pos = _save5
          end
          break
        end # end sequence

        unless _tmp
          _tmp = true
          self.pos = _save4
        end
        unless _tmp
          self.pos = _save1
          break
        end
        @result = begin;  create(Block, line, :contents => Array(es)) ; end
        _tmp = true
        unless _tmp
          self.pos = _save1
        end
        break
      end # end sequence

      break if _tmp
      self.pos = _save

      _save6 = self.pos
      while true # sequence
        _tmp = apply(:_line)
        line = @result
        unless _tmp
          self.pos = _save6
          break
        end
        _tmp = match_string("{")
        unless _tmp
          self.pos = _save6
          break
        end
        _tmp = apply(:_wsp)
        unless _tmp
          self.pos = _save6
          break
        end
        _save7 = self.pos
        _tmp = apply(:_expressions)
        @result = nil unless _tmp
        unless _tmp
          _tmp = true
          self.pos = _save7
        end
        es = @result
        unless _tmp
          self.pos = _save6
          break
        end
        _tmp = apply(:_wsp)
        unless _tmp
          self.pos = _save6
          break
        end
        _tmp = match_string("}")
        unless _tmp
          self.pos = _save6
          break
        end
        @result = begin;  create(Block, line, :contents => Array(es)) ; end
        _tmp = true
        unless _tmp
          self.pos = _save6
        end
        break
      end # end sequence

      break if _tmp
      self.pos = _save
      break
    end # end choice

    set_failed_rule :_block unless _tmp
    return _tmp
  end

  # list = line:line "[" wsp expressions?:es wsp "]" { create(List, line, :elements => Array(es)) }
  def _list

    _save = self.pos
    while true # sequence
      _tmp = apply(:_line)
      line = @result
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string("[")
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_wsp)
      unless _tmp
        self.pos = _save
        break
      end
      _save1 = self.pos
      _tmp = apply(:_expressions)
      @result = nil unless _tmp
      unless _tmp
        _tmp = true
        self.pos = _save1
      end
      es = @result
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_wsp)
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string("]")
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  create(List, line, :elements => Array(es)) ; end
      _tmp = true
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_list unless _tmp
    return _tmp
  end

  # composes = (line:line compose:l cont(pos) level2:r { create(Compose, line, :left => l, :right => r) } | line:line level2:l cont(pos) level2:r { create(Compose, line, :left => l, :right => r) })
  def _composes(pos)

    _save = self.pos
    while true # choice

      _save1 = self.pos
      while true # sequence
        _tmp = apply(:_line)
        line = @result
        unless _tmp
          self.pos = _save1
          break
        end
        _tmp = apply(:_compose)
        l = @result
        unless _tmp
          self.pos = _save1
          break
        end
        _tmp = apply_with_args(:_cont, pos)
        unless _tmp
          self.pos = _save1
          break
        end
        _tmp = apply(:_level2)
        r = @result
        unless _tmp
          self.pos = _save1
          break
        end
        @result = begin;  create(Compose, line, :left => l, :right => r) ; end
        _tmp = true
        unless _tmp
          self.pos = _save1
        end
        break
      end # end sequence

      break if _tmp
      self.pos = _save

      _save2 = self.pos
      while true # sequence
        _tmp = apply(:_line)
        line = @result
        unless _tmp
          self.pos = _save2
          break
        end
        _tmp = apply(:_level2)
        l = @result
        unless _tmp
          self.pos = _save2
          break
        end
        _tmp = apply_with_args(:_cont, pos)
        unless _tmp
          self.pos = _save2
          break
        end
        _tmp = apply(:_level2)
        r = @result
        unless _tmp
          self.pos = _save2
          break
        end
        @result = begin;  create(Compose, line, :left => l, :right => r) ; end
        _tmp = true
        unless _tmp
          self.pos = _save2
        end
        break
      end # end sequence

      break if _tmp
      self.pos = _save
      break
    end # end choice

    set_failed_rule :_composes unless _tmp
    return _tmp
  end

  # compose = @composes(current_position)
  def _compose
    _tmp = _composes(current_position)
    set_failed_rule :_compose unless _tmp
    return _tmp
  end

  # name = (line:line name:n op_letter:o { create(Postfix, line, :receiver => n, :operator => o) } | grouped | level0(false))
  def _name

    _save = self.pos
    while true # choice

      _save1 = self.pos
      while true # sequence
        _tmp = apply(:_line)
        line = @result
        unless _tmp
          self.pos = _save1
          break
        end
        _tmp = apply(:_name)
        n = @result
        unless _tmp
          self.pos = _save1
          break
        end
        _tmp = apply(:_op_letter)
        o = @result
        unless _tmp
          self.pos = _save1
          break
        end
        @result = begin;  create(Postfix, line, :receiver => n, :operator => o) ; end
        _tmp = true
        unless _tmp
          self.pos = _save1
        end
        break
      end # end sequence

      break if _tmp
      self.pos = _save
      _tmp = apply(:_grouped)
      break if _tmp
      self.pos = _save
      _tmp = apply_with_args(:_level0, false)
      break if _tmp
      self.pos = _save
      break
    end # end choice

    set_failed_rule :_name unless _tmp
    return _tmp
  end

  # args = "(" wsp expressions?:as wsp ")" { Array(as) }
  def _args

    _save = self.pos
    while true # sequence
      _tmp = match_string("(")
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_wsp)
      unless _tmp
        self.pos = _save
        break
      end
      _save1 = self.pos
      _tmp = apply(:_expressions)
      @result = nil unless _tmp
      unless _tmp
        _tmp = true
        self.pos = _save1
      end
      as = @result
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_wsp)
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string(")")
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  Array(as) ; end
      _tmp = true
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_args unless _tmp
    return _tmp
  end

  # call = (line:line call:c args:as { create(Call, line, :name => c, :arguments => as) } | line:line name:n args:as { create(Call, line, :name => n, :arguments => as) })
  def _call

    _save = self.pos
    while true # choice

      _save1 = self.pos
      while true # sequence
        _tmp = apply(:_line)
        line = @result
        unless _tmp
          self.pos = _save1
          break
        end
        _tmp = apply(:_call)
        c = @result
        unless _tmp
          self.pos = _save1
          break
        end
        _tmp = apply(:_args)
        as = @result
        unless _tmp
          self.pos = _save1
          break
        end
        @result = begin;  create(Call, line, :name => c, :arguments => as) ; end
        _tmp = true
        unless _tmp
          self.pos = _save1
        end
        break
      end # end sequence

      break if _tmp
      self.pos = _save

      _save2 = self.pos
      while true # sequence
        _tmp = apply(:_line)
        line = @result
        unless _tmp
          self.pos = _save2
          break
        end
        _tmp = apply(:_name)
        n = @result
        unless _tmp
          self.pos = _save2
          break
        end
        _tmp = apply(:_args)
        as = @result
        unless _tmp
          self.pos = _save2
          break
        end
        @result = begin;  create(Call, line, :name => n, :arguments => as) ; end
        _tmp = true
        unless _tmp
          self.pos = _save2
        end
        break
      end # end sequence

      break if _tmp
      self.pos = _save
      break
    end # end choice

    set_failed_rule :_call unless _tmp
    return _tmp
  end

  # infix_op = (operator | identifier:n &{ operator?(n) } { n })
  def _infix_op

    _save = self.pos
    while true # choice
      _tmp = apply(:_operator)
      break if _tmp
      self.pos = _save

      _save1 = self.pos
      while true # sequence
        _tmp = apply(:_identifier)
        n = @result
        unless _tmp
          self.pos = _save1
          break
        end
        _save2 = self.pos
        _tmp = begin;  operator?(n) ; end
        self.pos = _save2
        unless _tmp
          self.pos = _save1
          break
        end
        @result = begin;  n ; end
        _tmp = true
        unless _tmp
          self.pos = _save1
        end
        break
      end # end sequence

      break if _tmp
      self.pos = _save
      break
    end # end choice

    set_failed_rule :_infix_op unless _tmp
    return _tmp
  end

  # infix_c = cont(pos) (infix_op:o sig_wsp { o })+:os level3:e { o = os.shift                       [ Operator.new(@module, o),                         os.collect do |h|                           [private_target, Operator.new(@module, h, true)]                         end,                         e                       ]                     }
  def _infix_c(pos)

    _save = self.pos
    while true # sequence
      _tmp = apply_with_args(:_cont, pos)
      unless _tmp
        self.pos = _save
        break
      end
      _save1 = self.pos
      _ary = []

      _save2 = self.pos
      while true # sequence
        _tmp = apply(:_infix_op)
        o = @result
        unless _tmp
          self.pos = _save2
          break
        end
        _tmp = apply(:_sig_wsp)
        unless _tmp
          self.pos = _save2
          break
        end
        @result = begin;  o ; end
        _tmp = true
        unless _tmp
          self.pos = _save2
        end
        break
      end # end sequence

      if _tmp
        _ary << @result
        while true

          _save3 = self.pos
          while true # sequence
            _tmp = apply(:_infix_op)
            o = @result
            unless _tmp
              self.pos = _save3
              break
            end
            _tmp = apply(:_sig_wsp)
            unless _tmp
              self.pos = _save3
              break
            end
            @result = begin;  o ; end
            _tmp = true
            unless _tmp
              self.pos = _save3
            end
            break
          end # end sequence

          _ary << @result if _tmp
          break unless _tmp
        end
        _tmp = true
        @result = _ary
      else
        self.pos = _save1
      end
      os = @result
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_level3)
      e = @result
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  o = os.shift
                      [ Operator.new(@module, o),
                        os.collect do |h|
                          [private_target, Operator.new(@module, h, true)]
                        end,
                        e
                      ]
                    ; end
      _tmp = true
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_infix_c unless _tmp
    return _tmp
  end

  # infix_cs = infix_c(pos)+:bs { bs.flatten }
  def _infix_cs(pos)

    _save = self.pos
    while true # sequence
      _save1 = self.pos
      _ary = []
      _tmp = apply_with_args(:_infix_c, pos)
      if _tmp
        _ary << @result
        while true
          _tmp = apply_with_args(:_infix_c, pos)
          _ary << @result if _tmp
          break unless _tmp
        end
        _tmp = true
        @result = _ary
      else
        self.pos = _save1
      end
      bs = @result
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  bs.flatten ; end
      _tmp = true
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_infix_cs unless _tmp
    return _tmp
  end

  # infix = ({ current_position }:pos level3:l infix_cs(pos):c { resolve(nil, l, c).first } | infix_cs(current_position):c { c[0].private = true                       resolve(nil, private_target, c).first                     })
  def _infix

    _save = self.pos
    while true # choice

      _save1 = self.pos
      while true # sequence
        @result = begin;  current_position ; end
        _tmp = true
        pos = @result
        unless _tmp
          self.pos = _save1
          break
        end
        _tmp = apply(:_level3)
        l = @result
        unless _tmp
          self.pos = _save1
          break
        end
        _tmp = apply_with_args(:_infix_cs, pos)
        c = @result
        unless _tmp
          self.pos = _save1
          break
        end
        @result = begin;  resolve(nil, l, c).first ; end
        _tmp = true
        unless _tmp
          self.pos = _save1
        end
        break
      end # end sequence

      break if _tmp
      self.pos = _save

      _save2 = self.pos
      while true # sequence
        _tmp = apply_with_args(:_infix_cs, current_position)
        c = @result
        unless _tmp
          self.pos = _save2
          break
        end
        @result = begin;  c[0].private = true
                      resolve(nil, private_target, c).first
                    ; end
        _tmp = true
        unless _tmp
          self.pos = _save2
        end
        break
      end # end sequence

      break if _tmp
      self.pos = _save
      break
    end # end choice

    set_failed_rule :_infix unless _tmp
    return _tmp
  end

  # escapes = ("n" { "\n" } | "s" { " " } | "r" { "\r" } | "t" { "\t" } | "v" { "\v" } | "f" { "\f" } | "b" { "\b" } | "a" { "\a" } | "e" { "\e" } | "\\" { "\\" } | "\"" { "\"" } | "BS" { "\b" } | "HT" { "\t" } | "LF" { "\n" } | "VT" { "\v" } | "FF" { "\f" } | "CR" { "\r" } | "SO" { "\016" } | "SI" { "\017" } | "EM" { "\031" } | "FS" { "\034" } | "GS" { "\035" } | "RS" { "\036" } | "US" { "\037" } | "SP" { " " } | "NUL" { "\000" } | "SOH" { "\001" } | "STX" { "\002" } | "ETX" { "\003" } | "EOT" { "\004" } | "ENQ" { "\005" } | "ACK" { "\006" } | "BEL" { "\a" } | "DLE" { "\020" } | "DC1" { "\021" } | "DC2" { "\022" } | "DC3" { "\023" } | "DC4" { "\024" } | "NAK" { "\025" } | "SYN" { "\026" } | "ETB" { "\027" } | "CAN" { "\030" } | "SUB" { "\032" } | "ESC" { "\e" } | "DEL" { "\177" } | < . > { "\\" + text })
  def _escapes

    _save = self.pos
    while true # choice

      _save1 = self.pos
      while true # sequence
        _tmp = match_string("n")
        unless _tmp
          self.pos = _save1
          break
        end
        @result = begin;  "\n" ; end
        _tmp = true
        unless _tmp
          self.pos = _save1
        end
        break
      end # end sequence

      break if _tmp
      self.pos = _save

      _save2 = self.pos
      while true # sequence
        _tmp = match_string("s")
        unless _tmp
          self.pos = _save2
          break
        end
        @result = begin;  " " ; end
        _tmp = true
        unless _tmp
          self.pos = _save2
        end
        break
      end # end sequence

      break if _tmp
      self.pos = _save

      _save3 = self.pos
      while true # sequence
        _tmp = match_string("r")
        unless _tmp
          self.pos = _save3
          break
        end
        @result = begin;  "\r" ; end
        _tmp = true
        unless _tmp
          self.pos = _save3
        end
        break
      end # end sequence

      break if _tmp
      self.pos = _save

      _save4 = self.pos
      while true # sequence
        _tmp = match_string("t")
        unless _tmp
          self.pos = _save4
          break
        end
        @result = begin;  "\t" ; end
        _tmp = true
        unless _tmp
          self.pos = _save4
        end
        break
      end # end sequence

      break if _tmp
      self.pos = _save

      _save5 = self.pos
      while true # sequence
        _tmp = match_string("v")
        unless _tmp
          self.pos = _save5
          break
        end
        @result = begin;  "\v" ; end
        _tmp = true
        unless _tmp
          self.pos = _save5
        end
        break
      end # end sequence

      break if _tmp
      self.pos = _save

      _save6 = self.pos
      while true # sequence
        _tmp = match_string("f")
        unless _tmp
          self.pos = _save6
          break
        end
        @result = begin;  "\f" ; end
        _tmp = true
        unless _tmp
          self.pos = _save6
        end
        break
      end # end sequence

      break if _tmp
      self.pos = _save

      _save7 = self.pos
      while true # sequence
        _tmp = match_string("b")
        unless _tmp
          self.pos = _save7
          break
        end
        @result = begin;  "\b" ; end
        _tmp = true
        unless _tmp
          self.pos = _save7
        end
        break
      end # end sequence

      break if _tmp
      self.pos = _save

      _save8 = self.pos
      while true # sequence
        _tmp = match_string("a")
        unless _tmp
          self.pos = _save8
          break
        end
        @result = begin;  "\a" ; end
        _tmp = true
        unless _tmp
          self.pos = _save8
        end
        break
      end # end sequence

      break if _tmp
      self.pos = _save

      _save9 = self.pos
      while true # sequence
        _tmp = match_string("e")
        unless _tmp
          self.pos = _save9
          break
        end
        @result = begin;  "\e" ; end
        _tmp = true
        unless _tmp
          self.pos = _save9
        end
        break
      end # end sequence

      break if _tmp
      self.pos = _save

      _save10 = self.pos
      while true # sequence
        _tmp = match_string("\\")
        unless _tmp
          self.pos = _save10
          break
        end
        @result = begin;  "\\" ; end
        _tmp = true
        unless _tmp
          self.pos = _save10
        end
        break
      end # end sequence

      break if _tmp
      self.pos = _save

      _save11 = self.pos
      while true # sequence
        _tmp = match_string("\"")
        unless _tmp
          self.pos = _save11
          break
        end
        @result = begin;  "\"" ; end
        _tmp = true
        unless _tmp
          self.pos = _save11
        end
        break
      end # end sequence

      break if _tmp
      self.pos = _save

      _save12 = self.pos
      while true # sequence
        _tmp = match_string("BS")
        unless _tmp
          self.pos = _save12
          break
        end
        @result = begin;  "\b" ; end
        _tmp = true
        unless _tmp
          self.pos = _save12
        end
        break
      end # end sequence

      break if _tmp
      self.pos = _save

      _save13 = self.pos
      while true # sequence
        _tmp = match_string("HT")
        unless _tmp
          self.pos = _save13
          break
        end
        @result = begin;  "\t" ; end
        _tmp = true
        unless _tmp
          self.pos = _save13
        end
        break
      end # end sequence

      break if _tmp
      self.pos = _save

      _save14 = self.pos
      while true # sequence
        _tmp = match_string("LF")
        unless _tmp
          self.pos = _save14
          break
        end
        @result = begin;  "\n" ; end
        _tmp = true
        unless _tmp
          self.pos = _save14
        end
        break
      end # end sequence

      break if _tmp
      self.pos = _save

      _save15 = self.pos
      while true # sequence
        _tmp = match_string("VT")
        unless _tmp
          self.pos = _save15
          break
        end
        @result = begin;  "\v" ; end
        _tmp = true
        unless _tmp
          self.pos = _save15
        end
        break
      end # end sequence

      break if _tmp
      self.pos = _save

      _save16 = self.pos
      while true # sequence
        _tmp = match_string("FF")
        unless _tmp
          self.pos = _save16
          break
        end
        @result = begin;  "\f" ; end
        _tmp = true
        unless _tmp
          self.pos = _save16
        end
        break
      end # end sequence

      break if _tmp
      self.pos = _save

      _save17 = self.pos
      while true # sequence
        _tmp = match_string("CR")
        unless _tmp
          self.pos = _save17
          break
        end
        @result = begin;  "\r" ; end
        _tmp = true
        unless _tmp
          self.pos = _save17
        end
        break
      end # end sequence

      break if _tmp
      self.pos = _save

      _save18 = self.pos
      while true # sequence
        _tmp = match_string("SO")
        unless _tmp
          self.pos = _save18
          break
        end
        @result = begin;  "\016" ; end
        _tmp = true
        unless _tmp
          self.pos = _save18
        end
        break
      end # end sequence

      break if _tmp
      self.pos = _save

      _save19 = self.pos
      while true # sequence
        _tmp = match_string("SI")
        unless _tmp
          self.pos = _save19
          break
        end
        @result = begin;  "\017" ; end
        _tmp = true
        unless _tmp
          self.pos = _save19
        end
        break
      end # end sequence

      break if _tmp
      self.pos = _save

      _save20 = self.pos
      while true # sequence
        _tmp = match_string("EM")
        unless _tmp
          self.pos = _save20
          break
        end
        @result = begin;  "\031" ; end
        _tmp = true
        unless _tmp
          self.pos = _save20
        end
        break
      end # end sequence

      break if _tmp
      self.pos = _save

      _save21 = self.pos
      while true # sequence
        _tmp = match_string("FS")
        unless _tmp
          self.pos = _save21
          break
        end
        @result = begin;  "\034" ; end
        _tmp = true
        unless _tmp
          self.pos = _save21
        end
        break
      end # end sequence

      break if _tmp
      self.pos = _save

      _save22 = self.pos
      while true # sequence
        _tmp = match_string("GS")
        unless _tmp
          self.pos = _save22
          break
        end
        @result = begin;  "\035" ; end
        _tmp = true
        unless _tmp
          self.pos = _save22
        end
        break
      end # end sequence

      break if _tmp
      self.pos = _save

      _save23 = self.pos
      while true # sequence
        _tmp = match_string("RS")
        unless _tmp
          self.pos = _save23
          break
        end
        @result = begin;  "\036" ; end
        _tmp = true
        unless _tmp
          self.pos = _save23
        end
        break
      end # end sequence

      break if _tmp
      self.pos = _save

      _save24 = self.pos
      while true # sequence
        _tmp = match_string("US")
        unless _tmp
          self.pos = _save24
          break
        end
        @result = begin;  "\037" ; end
        _tmp = true
        unless _tmp
          self.pos = _save24
        end
        break
      end # end sequence

      break if _tmp
      self.pos = _save

      _save25 = self.pos
      while true # sequence
        _tmp = match_string("SP")
        unless _tmp
          self.pos = _save25
          break
        end
        @result = begin;  " " ; end
        _tmp = true
        unless _tmp
          self.pos = _save25
        end
        break
      end # end sequence

      break if _tmp
      self.pos = _save

      _save26 = self.pos
      while true # sequence
        _tmp = match_string("NUL")
        unless _tmp
          self.pos = _save26
          break
        end
        @result = begin;  "\000" ; end
        _tmp = true
        unless _tmp
          self.pos = _save26
        end
        break
      end # end sequence

      break if _tmp
      self.pos = _save

      _save27 = self.pos
      while true # sequence
        _tmp = match_string("SOH")
        unless _tmp
          self.pos = _save27
          break
        end
        @result = begin;  "\001" ; end
        _tmp = true
        unless _tmp
          self.pos = _save27
        end
        break
      end # end sequence

      break if _tmp
      self.pos = _save

      _save28 = self.pos
      while true # sequence
        _tmp = match_string("STX")
        unless _tmp
          self.pos = _save28
          break
        end
        @result = begin;  "\002" ; end
        _tmp = true
        unless _tmp
          self.pos = _save28
        end
        break
      end # end sequence

      break if _tmp
      self.pos = _save

      _save29 = self.pos
      while true # sequence
        _tmp = match_string("ETX")
        unless _tmp
          self.pos = _save29
          break
        end
        @result = begin;  "\003" ; end
        _tmp = true
        unless _tmp
          self.pos = _save29
        end
        break
      end # end sequence

      break if _tmp
      self.pos = _save

      _save30 = self.pos
      while true # sequence
        _tmp = match_string("EOT")
        unless _tmp
          self.pos = _save30
          break
        end
        @result = begin;  "\004" ; end
        _tmp = true
        unless _tmp
          self.pos = _save30
        end
        break
      end # end sequence

      break if _tmp
      self.pos = _save

      _save31 = self.pos
      while true # sequence
        _tmp = match_string("ENQ")
        unless _tmp
          self.pos = _save31
          break
        end
        @result = begin;  "\005" ; end
        _tmp = true
        unless _tmp
          self.pos = _save31
        end
        break
      end # end sequence

      break if _tmp
      self.pos = _save

      _save32 = self.pos
      while true # sequence
        _tmp = match_string("ACK")
        unless _tmp
          self.pos = _save32
          break
        end
        @result = begin;  "\006" ; end
        _tmp = true
        unless _tmp
          self.pos = _save32
        end
        break
      end # end sequence

      break if _tmp
      self.pos = _save

      _save33 = self.pos
      while true # sequence
        _tmp = match_string("BEL")
        unless _tmp
          self.pos = _save33
          break
        end
        @result = begin;  "\a" ; end
        _tmp = true
        unless _tmp
          self.pos = _save33
        end
        break
      end # end sequence

      break if _tmp
      self.pos = _save

      _save34 = self.pos
      while true # sequence
        _tmp = match_string("DLE")
        unless _tmp
          self.pos = _save34
          break
        end
        @result = begin;  "\020" ; end
        _tmp = true
        unless _tmp
          self.pos = _save34
        end
        break
      end # end sequence

      break if _tmp
      self.pos = _save

      _save35 = self.pos
      while true # sequence
        _tmp = match_string("DC1")
        unless _tmp
          self.pos = _save35
          break
        end
        @result = begin;  "\021" ; end
        _tmp = true
        unless _tmp
          self.pos = _save35
        end
        break
      end # end sequence

      break if _tmp
      self.pos = _save

      _save36 = self.pos
      while true # sequence
        _tmp = match_string("DC2")
        unless _tmp
          self.pos = _save36
          break
        end
        @result = begin;  "\022" ; end
        _tmp = true
        unless _tmp
          self.pos = _save36
        end
        break
      end # end sequence

      break if _tmp
      self.pos = _save

      _save37 = self.pos
      while true # sequence
        _tmp = match_string("DC3")
        unless _tmp
          self.pos = _save37
          break
        end
        @result = begin;  "\023" ; end
        _tmp = true
        unless _tmp
          self.pos = _save37
        end
        break
      end # end sequence

      break if _tmp
      self.pos = _save

      _save38 = self.pos
      while true # sequence
        _tmp = match_string("DC4")
        unless _tmp
          self.pos = _save38
          break
        end
        @result = begin;  "\024" ; end
        _tmp = true
        unless _tmp
          self.pos = _save38
        end
        break
      end # end sequence

      break if _tmp
      self.pos = _save

      _save39 = self.pos
      while true # sequence
        _tmp = match_string("NAK")
        unless _tmp
          self.pos = _save39
          break
        end
        @result = begin;  "\025" ; end
        _tmp = true
        unless _tmp
          self.pos = _save39
        end
        break
      end # end sequence

      break if _tmp
      self.pos = _save

      _save40 = self.pos
      while true # sequence
        _tmp = match_string("SYN")
        unless _tmp
          self.pos = _save40
          break
        end
        @result = begin;  "\026" ; end
        _tmp = true
        unless _tmp
          self.pos = _save40
        end
        break
      end # end sequence

      break if _tmp
      self.pos = _save

      _save41 = self.pos
      while true # sequence
        _tmp = match_string("ETB")
        unless _tmp
          self.pos = _save41
          break
        end
        @result = begin;  "\027" ; end
        _tmp = true
        unless _tmp
          self.pos = _save41
        end
        break
      end # end sequence

      break if _tmp
      self.pos = _save

      _save42 = self.pos
      while true # sequence
        _tmp = match_string("CAN")
        unless _tmp
          self.pos = _save42
          break
        end
        @result = begin;  "\030" ; end
        _tmp = true
        unless _tmp
          self.pos = _save42
        end
        break
      end # end sequence

      break if _tmp
      self.pos = _save

      _save43 = self.pos
      while true # sequence
        _tmp = match_string("SUB")
        unless _tmp
          self.pos = _save43
          break
        end
        @result = begin;  "\032" ; end
        _tmp = true
        unless _tmp
          self.pos = _save43
        end
        break
      end # end sequence

      break if _tmp
      self.pos = _save

      _save44 = self.pos
      while true # sequence
        _tmp = match_string("ESC")
        unless _tmp
          self.pos = _save44
          break
        end
        @result = begin;  "\e" ; end
        _tmp = true
        unless _tmp
          self.pos = _save44
        end
        break
      end # end sequence

      break if _tmp
      self.pos = _save

      _save45 = self.pos
      while true # sequence
        _tmp = match_string("DEL")
        unless _tmp
          self.pos = _save45
          break
        end
        @result = begin;  "\177" ; end
        _tmp = true
        unless _tmp
          self.pos = _save45
        end
        break
      end # end sequence

      break if _tmp
      self.pos = _save

      _save46 = self.pos
      while true # sequence
        _text_start = self.pos
        _tmp = get_byte
        if _tmp
          text = get_text(_text_start)
        end
        unless _tmp
          self.pos = _save46
          break
        end
        @result = begin;  "\\" + text ; end
        _tmp = true
        unless _tmp
          self.pos = _save46
        end
        break
      end # end sequence

      break if _tmp
      self.pos = _save
      break
    end # end choice

    set_failed_rule :_escapes unless _tmp
    return _tmp
  end

  # number_escapes = (/[xX]/ < /[0-9a-fA-F]{1,5}/ > { [text.to_i(16)].pack("U") } | < /\d{1,6}/ > { [text.to_i].pack("U") } | /[oO]/ < /[0-7]{1,7}/ > { [text.to_i(16)].pack("U") } | /[uU]/ < /[0-9a-fA-F]{4}/ > { [text.to_i(16)].pack("U") })
  def _number_escapes

    _save = self.pos
    while true # choice

      _save1 = self.pos
      while true # sequence
        _tmp = scan(/\A(?-mix:[xX])/)
        unless _tmp
          self.pos = _save1
          break
        end
        _text_start = self.pos
        _tmp = scan(/\A(?-mix:[0-9a-fA-F]{1,5})/)
        if _tmp
          text = get_text(_text_start)
        end
        unless _tmp
          self.pos = _save1
          break
        end
        @result = begin;  [text.to_i(16)].pack("U") ; end
        _tmp = true
        unless _tmp
          self.pos = _save1
        end
        break
      end # end sequence

      break if _tmp
      self.pos = _save

      _save2 = self.pos
      while true # sequence
        _text_start = self.pos
        _tmp = scan(/\A(?-mix:\d{1,6})/)
        if _tmp
          text = get_text(_text_start)
        end
        unless _tmp
          self.pos = _save2
          break
        end
        @result = begin;  [text.to_i].pack("U") ; end
        _tmp = true
        unless _tmp
          self.pos = _save2
        end
        break
      end # end sequence

      break if _tmp
      self.pos = _save

      _save3 = self.pos
      while true # sequence
        _tmp = scan(/\A(?-mix:[oO])/)
        unless _tmp
          self.pos = _save3
          break
        end
        _text_start = self.pos
        _tmp = scan(/\A(?-mix:[0-7]{1,7})/)
        if _tmp
          text = get_text(_text_start)
        end
        unless _tmp
          self.pos = _save3
          break
        end
        @result = begin;  [text.to_i(16)].pack("U") ; end
        _tmp = true
        unless _tmp
          self.pos = _save3
        end
        break
      end # end sequence

      break if _tmp
      self.pos = _save

      _save4 = self.pos
      while true # sequence
        _tmp = scan(/\A(?-mix:[uU])/)
        unless _tmp
          self.pos = _save4
          break
        end
        _text_start = self.pos
        _tmp = scan(/\A(?-mix:[0-9a-fA-F]{4})/)
        if _tmp
          text = get_text(_text_start)
        end
        unless _tmp
          self.pos = _save4
          break
        end
        @result = begin;  [text.to_i(16)].pack("U") ; end
        _tmp = true
        unless _tmp
          self.pos = _save4
        end
        break
      end # end sequence

      break if _tmp
      self.pos = _save
      break
    end # end choice

    set_failed_rule :_number_escapes unless _tmp
    return _tmp
  end

  # top = expression:e { callback(e) }
  def _top

    _save = self.pos
    while true # sequence
      _tmp = apply(:_expression)
      e = @result
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  callback(e) ; end
      _tmp = true
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_top unless _tmp
    return _tmp
  end

  # tree = { current_column }:c top:x (delim(c) top)*:xs { [x] + Array(xs) }
  def _tree

    _save = self.pos
    while true # sequence
      @result = begin;  current_column ; end
      _tmp = true
      c = @result
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_top)
      x = @result
      unless _tmp
        self.pos = _save
        break
      end
      _ary = []
      while true

        _save2 = self.pos
        while true # sequence
          _tmp = apply_with_args(:_delim, c)
          unless _tmp
            self.pos = _save2
            break
          end
          _tmp = apply(:_top)
          unless _tmp
            self.pos = _save2
          end
          break
        end # end sequence

        _ary << @result if _tmp
        break unless _tmp
      end
      _tmp = true
      @result = _ary
      xs = @result
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  [x] + Array(xs) ; end
      _tmp = true
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_tree unless _tmp
    return _tmp
  end

  # root = shebang? wsp tree:es wsp !. { Array(es) }
  def _root

    _save = self.pos
    while true # sequence
      _save1 = self.pos
      _tmp = apply(:_shebang)
      unless _tmp
        _tmp = true
        self.pos = _save1
      end
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_wsp)
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_tree)
      es = @result
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_wsp)
      unless _tmp
        self.pos = _save
        break
      end
      _save2 = self.pos
      _tmp = get_byte
      _tmp = _tmp ? nil : true
      self.pos = _save2
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  Array(es) ; end
      _tmp = true
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_root unless _tmp
    return _tmp
  end

  Rules = {}
  Rules[:_sp] = rule_info("sp", "(\" \" | \"\\t\" | comment)*")
  Rules[:_wsp] = rule_info("wsp", "(\" \" | \"\\t\" | \"\\n\" | comment)*")
  Rules[:_sig_sp] = rule_info("sig_sp", "(\" \" | \"\\t\" | comment)+")
  Rules[:_sig_wsp] = rule_info("sig_wsp", "(\" \" | \"\\t\" | \"\\n\" | comment)+")
  Rules[:_shebang] = rule_info("shebang", "\"\#!\" /.*?$/")
  Rules[:_cont] = rule_info("cont", "((\"\\n\" sp)+ &{ continue?(p) } | sig_sp cont(p)? | !\"(\")")
  Rules[:_line] = rule_info("line", "{ current_line }")
  Rules[:_op_letter] = rule_info("op_letter", "!\"`\" < /[\\p{S}!@\#%&*\\-\\\\.\\/\\?]/u > { text.to_sym }")
  Rules[:_operator] = rule_info("operator", "< !\"~\" \":\"? op_letter+ > { text.to_sym }")
  Rules[:_identifier] = rule_info("identifier", "< /[\\p{Ll}_][\\p{L}\\d\\-_]*/u > { text.tr(\"-\", \"_\").to_sym }")
  Rules[:_grouped] = rule_info("grouped", "\"(\" wsp expression:x wsp \")\" { x }")
  Rules[:_comment] = rule_info("comment", "(/--.*?$/ | multi_comment)")
  Rules[:_multi_comment] = rule_info("multi_comment", "\"{-\" in_multi")
  Rules[:_in_multi] = rule_info("in_multi", "(/[^\\-\\{\\}]*/ \"-}\" | /[^\\-\\{\\}]*/ \"{-\" in_multi /[^\\-\\{\\}]*/ \"-}\" | /[^\\-\\{\\}]*/ /[-{}]/ in_multi)")
  Rules[:_delim] = rule_info("delim", "(wsp \",\" wsp | (sp \"\\n\" sp)+ &{ current_column >= c })")
  Rules[:_expression] = rule_info("expression", "level4")
  Rules[:_one_expression] = rule_info("one_expression", "wsp expression:e wsp !. { e }")
  Rules[:_expressions] = rule_info("expressions", "{ current_column }:c expression:x (delim(c) expression)*:xs { [x] + Array(xs) }")
  Rules[:_level0] = rule_info("level0", "(number | quote | quasi_quote | unquote | string | constant | word(no_op) | block | list | prefix)")
  Rules[:_level1] = rule_info("level1", "(call | grouped | level0(true))")
  Rules[:_level2] = rule_info("level2", "(postfix | level1)")
  Rules[:_level3] = rule_info("level3", "(compose | level2)")
  Rules[:_level4] = rule_info("level4", "(language | infix | level3)")
  Rules[:_number] = rule_info("number", "(line:line < /[\\+\\-]?0[oO][0-7]+/ > { create(Primitive, line, :value => text.to_i(8)) } | line:line < /[\\+\\-]?0[xX][\\da-fA-F]+/ > { create(Primitive, line, :value => text.to_i(16)) } | line:line < /[\\+\\-]?\\d+(\\.\\d+)?[eE][\\+\\-]?\\d+/ > { create(Literal, line, :value => text.to_f) } | line:line < /[\\+\\-]?\\d+\\.\\d+/ > { create(Literal, line, :value => text.to_f) } | line:line < /[\\+\\-]?\\d+/ > { create(Primitive, line, :value => text.to_i) })")
  Rules[:_language] = rule_info("language", "\"\#language\" wsp identifier:n { set_lang(n) } %lang.root")
  Rules[:_quote] = rule_info("quote", "line:line \"'\" level2:e { create(Quote, line, :expression => e) }")
  Rules[:_quasi_quote] = rule_info("quasi_quote", "line:line \"`\" level2:e { create(QuasiQuote, line, :expression => e) }")
  Rules[:_unquote] = rule_info("unquote", "line:line \"~\" level2:e { create(Unquote, line, :expression => e) }")
  Rules[:_escape] = rule_info("escape", "(number_escapes | escapes)")
  Rules[:_str_seq] = rule_info("str_seq", "< /[^\\\\\"]+/ > { text }")
  Rules[:_string] = rule_info("string", "line:line \"\\\"\" < (\"\\\\\" escape | str_seq)*:c > \"\\\"\" { create(StringLiteral, line,                         :value => c.join,                         :raw => text.gsub(\"\\\\\\\"\", \"\\\"\"))                     }")
  Rules[:_constant_name] = rule_info("constant_name", "< /[A-Z][a-zA-Z0-9_]*/ > { text.to_sym }")
  Rules[:_constant] = rule_info("constant", "line:line constant_name:n { create(Constant, line, :name => n) }")
  Rules[:_word] = rule_info("word", "line:line identifier:n !{ no_op && operator?(n) } { create(Word, line, :text => n) }")
  Rules[:_prefix] = rule_info("prefix", "line:line op_letter:o level2:e { create(Prefix, line, :receiver => e, :operator => o) }")
  Rules[:_postfix] = rule_info("postfix", "(line:line postfix:e op_letter:o { create(Postfix, line, :receiver => e, :operator => o) } | line:line level1:e op_letter:o { create(Postfix, line, :receiver => e, :operator => o) })")
  Rules[:_block] = rule_info("block", "(line:line \":\" !op_letter wsp expressions?:es (wsp \";\")? { create(Block, line, :contents => Array(es)) } | line:line \"{\" wsp expressions?:es wsp \"}\" { create(Block, line, :contents => Array(es)) })")
  Rules[:_list] = rule_info("list", "line:line \"[\" wsp expressions?:es wsp \"]\" { create(List, line, :elements => Array(es)) }")
  Rules[:_composes] = rule_info("composes", "(line:line compose:l cont(pos) level2:r { create(Compose, line, :left => l, :right => r) } | line:line level2:l cont(pos) level2:r { create(Compose, line, :left => l, :right => r) })")
  Rules[:_compose] = rule_info("compose", "@composes(current_position)")
  Rules[:_name] = rule_info("name", "(line:line name:n op_letter:o { create(Postfix, line, :receiver => n, :operator => o) } | grouped | level0(false))")
  Rules[:_args] = rule_info("args", "\"(\" wsp expressions?:as wsp \")\" { Array(as) }")
  Rules[:_call] = rule_info("call", "(line:line call:c args:as { create(Call, line, :name => c, :arguments => as) } | line:line name:n args:as { create(Call, line, :name => n, :arguments => as) })")
  Rules[:_infix_op] = rule_info("infix_op", "(operator | identifier:n &{ operator?(n) } { n })")
  Rules[:_infix_c] = rule_info("infix_c", "cont(pos) (infix_op:o sig_wsp { o })+:os level3:e { o = os.shift                       [ Operator.new(@module, o),                         os.collect do |h|                           [private_target, Operator.new(@module, h, true)]                         end,                         e                       ]                     }")
  Rules[:_infix_cs] = rule_info("infix_cs", "infix_c(pos)+:bs { bs.flatten }")
  Rules[:_infix] = rule_info("infix", "({ current_position }:pos level3:l infix_cs(pos):c { resolve(nil, l, c).first } | infix_cs(current_position):c { c[0].private = true                       resolve(nil, private_target, c).first                     })")
  Rules[:_escapes] = rule_info("escapes", "(\"n\" { \"\\n\" } | \"s\" { \" \" } | \"r\" { \"\\r\" } | \"t\" { \"\\t\" } | \"v\" { \"\\v\" } | \"f\" { \"\\f\" } | \"b\" { \"\\b\" } | \"a\" { \"\\a\" } | \"e\" { \"\\e\" } | \"\\\\\" { \"\\\\\" } | \"\\\"\" { \"\\\"\" } | \"BS\" { \"\\b\" } | \"HT\" { \"\\t\" } | \"LF\" { \"\\n\" } | \"VT\" { \"\\v\" } | \"FF\" { \"\\f\" } | \"CR\" { \"\\r\" } | \"SO\" { \"\\016\" } | \"SI\" { \"\\017\" } | \"EM\" { \"\\031\" } | \"FS\" { \"\\034\" } | \"GS\" { \"\\035\" } | \"RS\" { \"\\036\" } | \"US\" { \"\\037\" } | \"SP\" { \" \" } | \"NUL\" { \"\\000\" } | \"SOH\" { \"\\001\" } | \"STX\" { \"\\002\" } | \"ETX\" { \"\\003\" } | \"EOT\" { \"\\004\" } | \"ENQ\" { \"\\005\" } | \"ACK\" { \"\\006\" } | \"BEL\" { \"\\a\" } | \"DLE\" { \"\\020\" } | \"DC1\" { \"\\021\" } | \"DC2\" { \"\\022\" } | \"DC3\" { \"\\023\" } | \"DC4\" { \"\\024\" } | \"NAK\" { \"\\025\" } | \"SYN\" { \"\\026\" } | \"ETB\" { \"\\027\" } | \"CAN\" { \"\\030\" } | \"SUB\" { \"\\032\" } | \"ESC\" { \"\\e\" } | \"DEL\" { \"\\177\" } | < . > { \"\\\\\" + text })")
  Rules[:_number_escapes] = rule_info("number_escapes", "(/[xX]/ < /[0-9a-fA-F]{1,5}/ > { [text.to_i(16)].pack(\"U\") } | < /\\d{1,6}/ > { [text.to_i].pack(\"U\") } | /[oO]/ < /[0-7]{1,7}/ > { [text.to_i(16)].pack(\"U\") } | /[uU]/ < /[0-9a-fA-F]{4}/ > { [text.to_i(16)].pack(\"U\") })")
  Rules[:_top] = rule_info("top", "expression:e { callback(e) }")
  Rules[:_tree] = rule_info("tree", "{ current_column }:c top:x (delim(c) top)*:xs { [x] + Array(xs) }")
  Rules[:_root] = rule_info("root", "shebang? wsp tree:es wsp !. { Array(es) }")
  # :startdoc:
end
