# frozen_string_literal: true

# Contains features used to generate scenario reports and summaries.
module Report
  module_function

  # Components may contain one of these keys to define the content of the
  # component.
  CONTENT_KEYS = %i(h1 h2 h3 h4 h5 h6 text chart).freeze

  # Contains all keys which may be assigned to a component.
  VALID_KEYS = (CONTENT_KEYS + %i(if children)).freeze

  def build(report)
    build_components(report)
  end

  # Internal: Given an array of component definitions, converts each one
  # recusrively into a Component.
  #
  # Returns an array of Report::Component objects.
  def build_components(definitions)
    Array(definitions).map { |child| build_component(child.symbolize_keys) }
  end

  # Internal: Given a single component definition, creates a Component.
  #
  # Sets rules, and also converts all child components.
  #
  # Returns a Report::Component.
  def build_component(definition)
    ComponentValidator.call(definition)

    ruleset =
      if definition[:if]
        RuleSet.new([parse_rule_string(definition[:if])])
      else
        RuleSet.new
      end

    Report::Component.new(
      extract_content(definition),
      ruleset,
      build_components(definition[:children])
    )
  end

  # Internal: Parses a rule string into a working Rule.
  #
  # For example
  #   parse_rule_string('future(total_co2_emissions) > 1000')
  #   # => Report::Rule
  #
  # Returns a Rule or Rule-compatible object which responds to 'call'.
  def parse_rule_string(rule_str)
    # User may set a rule to true or false explicity while building a report.
    return LiteralOperand.new(rule_str) if rule_str == true || rule_str == false

    left_operand, operator, right_operand = rule_str.strip.split(' ')

    Rule.new([
      parse_operand(left_operand),
      parse_operand(right_operand)
    ], Operators[operator.to_sym])
  end

  # Internal: Parses a single operand in a rule into something which may be used
  # as an operand in a Rule.
  #
  # Returns an object which reponds to 'call'. Raises an error if the operand
  # couldn't be parsed.
  def parse_operand(operand)
    if (match = operand.match(/(?<period>present|future)\((?<query>[^)]+)\)/))
      # Matches a future(...) or present(...) call within a rule string.
      Report::QueryOperand.public_send(match[:period], match[:query].to_sym)
    elsif operand =~ /\d+(?:\.\d+)?/
      Report::LiteralOperand.new(Float(operand))
    elsif operand == 'true'
      Report::LiteralOperand.new(true)
    elsif operand == 'false'
      Report::LiteralOperand.new(false)
    else
      raise "Unknown operand #{ operand }"
    end
  end

  def extract_content(definition)
    if (attribute = CONTENT_KEYS.detect { |key| definition.key?(key) })
      return { type: attribute, content: definition[attribute] }
    end

    {} # No content; this is a container for other components.
  end
end
