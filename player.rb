class Player
  # This is completely arbitrary.
  MIN_GAMES = 25

  attr_reader :name

  def initialize(name)
    @name = name.freeze
    @games = Hash.new(0)
    @wins = Hash.new(0)
  end

  [:spy, :res].each { |team|
    define_method("#{team}_wins") { @wins[team] }
    define_method("#{team}_games") { @games[team] }
    define_method("#{team}_winrate") { @wins[team] / @games[team].to_f }
    define_method("#{team}_significant?") { @games[team] >= MIN_GAMES }

    define_method("play_#{team}") { |win: false|
      @games[team] += 1
      @wins[team] += 1 if win
    }
  }

  def stats(type)
    case type
    when :res; [res_wins, res_games, res_winrate]
    when :spy; [spy_wins, spy_games, spy_winrate]
    else [wins, games, winrate]
    end
  end

  def to_s(type: nil)
    "%16s: %3d/%3d %.3f" % ([@name] + stats(type))
  end

  def wins
    @wins.values.reduce(:+)
  end

  def games
    @games.values.reduce(:+)
  end

  def winrate
    wins.to_f / games
  end

  def significant?
    games >= MIN_GAMES
  end
end
