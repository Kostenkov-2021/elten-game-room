module GameRoomLocalization
  class PluralRule
    OPERATORS = [%w[||], %w[&&], %w[== !=], %w[< <= > >=], %w[+ -], %w[* / %]].freeze

    def initialize(expression)
      source = expression.to_s.gsub(/\s+/, "")
      @tokens = source.scan(/\d+|n|&&|\|\||==|!=|<=|>=|[?:()!+*\/%<>-]/)
      if source.empty? || source.length > 2048 || @tokens.length > 256 || @tokens.join != source
        raise ArgumentError, "invalid plural expression"
      end
      @position = 0
      @tree = expression_tree
      raise ArgumentError, "unexpected plural expression token" if @position != @tokens.length
      @tokens = nil
    end

    def index(count)
      evaluate(@tree, count.to_i)
    rescue ZeroDivisionError
      nil
    end

    private

    def take(token)
      return false unless @tokens[@position] == token
      @position += 1
      true
    end

    def expect(token)
      raise ArgumentError, "invalid plural expression" unless take(token)
    end

    def expression_tree
      tree = binary_tree(0)
      if take("?")
        positive = expression_tree
        expect(":")
        tree = ["?", tree, positive, expression_tree]
      end
      tree
    end

    def binary_tree(level)
      return unary_tree if level == OPERATORS.length
      tree = binary_tree(level + 1)
      while OPERATORS[level].include?(@tokens[@position])
        operator = @tokens[@position]
        @position += 1
        tree = [operator, tree, binary_tree(level + 1)]
      end
      tree
    end

    def unary_tree
      return ["!", unary_tree] if take("!")
      return ["negate", unary_tree] if take("-")
      return unary_tree if take("+")
      if take("(")
        tree = expression_tree
        expect(")")
        return tree
      end
      token = @tokens[@position]
      raise ArgumentError, "invalid plural operand" unless token && (token == "n" || token.match?(/\A\d+\z/))
      @position += 1
      token == "n" ? :n : token.to_i
    end

    def evaluate(tree, count)
      return count if tree == :n
      return tree if tree.is_a?(Integer)
      operator, left, right, other = tree
      a = evaluate(left, count)
      case operator
      when "?" then evaluate(a != 0 ? right : other, count)
      when "!" then a == 0 ? 1 : 0
      when "negate" then -a
      when "&&" then a != 0 && evaluate(right, count) != 0 ? 1 : 0
      when "||" then a != 0 || evaluate(right, count) != 0 ? 1 : 0
      else
        b = evaluate(right, count)
        case operator
        when "+" then a + b
        when "-" then a - b
        when "*" then a * b
        when "/" then quotient(a, b)
        when "%" then a - quotient(a, b) * b
        when "==" then a == b ? 1 : 0
        when "!=" then a != b ? 1 : 0
        when "<" then a < b ? 1 : 0
        when "<=" then a <= b ? 1 : 0
        when ">" then a > b ? 1 : 0
        when ">=" then a >= b ? 1 : 0
        end
      end
    end

    # Gettext expressions use C integer arithmetic (truncate toward zero),
    # including negative intermediate values in otherwise positive counts.
    def quotient(a, b)
      value = a.abs.div(b.abs)
      (a < 0) != (b < 0) ? -value : value
    end
  end
end
