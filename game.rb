class Game
  NAME_AND_ROLE = /(\w+)(?: \((.*)\))?/

  attr_reader :start_time, :num_players, :num_spies
  attr_reader :mission_end_time, :assassination_end_time
  attr_reader :order
  attr_reader :avalon, :avalon_roles, :avalon_variants
  attr_reader :mission_success
  attr_reader :winning_side
  attr_reader :assassin_target
  attr_reader :roles
  attr_reader :resistance_players, :spy_players

  alias :avalon? :avalon

  def initialize(start_time, num_players, num_spies)
    @start_time = start_time
    @mission_end_time = nil
    @assassination_end_time = nil

    @num_players = num_players
    @num_spies = num_spies
    @start_complete = !num_players.nil? && !num_spies.nil?

    @order = nil
    @avalon = false
    @avalon_roles = [].freeze
    @avalon_variants = [].freeze
    @mission_success = [].freeze
    @winning_side = nil
    @assassin_target = nil
    @roles = {}.freeze
    @resistance_players = [].freeze
    @spy_players = [].freeze
  end

  def complete?
    @winning_side && @start_complete
  end

  def res_score
    @res_score ||= @mission_success.count(true)
  end

  def spy_score
    @spy_score ||= @mission_success.count(false)
  end

  def winning_players
    case @winning_side
    when :resistance; @resistance_players
    when :spies; @spy_players
    when nil; []
    else raise "Winning players of unrecognized side #{@winning_side}"
    end
  end

  def assassination_duration
    # Only exists in Avalon games with an assassination.
    return 0 unless @avalon && res_score == 3
    @assassination_end_time - @mission_end_time
  end

  def duration
    return 0 unless end_time && @start_time
    end_time - @start_time
  end

  def end_time
    @avalon ? @assassination_end_time : @mission_end_time
  end

  def to_s
    type = @avalon ? 'Avalon' : 'Base'
    "Game #{start_time} #{num_players} #{type} #{res_score}-#{spy_score} R: #{@resistance_players} S: #{@spy_players} W: #{winning_players}"
  end

  def order=(order)
    raise "Order is #{@order} on #{self}, can't set to #{order}" if @order
    @order = order.freeze
  end

  def avalon!(roles:, variants:)
    @avalon = true
    @avalon_roles = roles.freeze
    @avalon_variants = variants.freeze
  end

  def spies=(l)
    raise "Spies are #{@spy_players} on #{self}, can't set to #{l}" unless @spy_players.empty?
    @spy_players = parse_role_list(l)
  end

  def resistance=(l)
    raise "Resistance are #{@resistance_players} on #{self}, can't set to #{l}" unless @resistance_players.empty?
    @resistance_players = parse_role_list(l)
  end

  def mission_success=(success)
    if @mission_success
      if @mission_success.size > success.size
        raise "can't replace #{self} mission success #{@mission_success} with smaller #{success}"
      elsif !@mission_success.each_with_index { |s, i| success[i] == s }
        raise "can't replace #{self} mission success #{@mission_success} with inconsistent #{success}"
      end
    end
    @mission_success = success.freeze
    # Clear caches on res_score and spy_score
    @res_score = nil
    @spy_score = nil
  end

  def assassinate!(target, time, winner:)
    raise "Already assassinated #{@assassin_target} on #{self}, can't assassinate #{target}" if @assassin_target
    @assassin_target = target
    @assassination_end_time = time
    @winning_side = winner
  end

  def begin_assassination(time)
    unless @avalon
      # We'll be forgiving for games that are started from incomplete logs...
      # "from incomplete logs" is currently detected by num_{players,spies} being nil
      if @start_complete
        raise "assassination in a non-avalon game #{self}"
      else
        @avalon = true
      end
    end

    # TODO: We'd like to check @avalon here, but some Assassin games don't get that set (incomplete logs, etc.)
    raise "Missions already ended at #{@mission_end_time} on #{self}, can't assassinate" if @mission_end_time
    @mission_end_time = time
  end

  def win_on_missions(winner, time)
    raise "Missions already ended at #{@mission_end_time} on #{self}, can't let #{winner} win on missions" if @mission_end_time
    raise "#{@winning_side} already won on #{self}, can't let #{winner} win on missions" if @winning_side
    @winning_side = winner
    @mission_end_time = time
  end

  private

  def parse_role_list(l)
    results = []
    roles = {}
    l.split(', ').each { |x|
      m = NAME_AND_ROLE.match(x)
      raise "What is #{x}???" unless m

      results << m[1]
      roles[m[1]] = m[2] if m[2]
    }
    @roles = @roles.merge(roles).freeze
    results.freeze
  end
end
