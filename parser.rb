require_relative 'game'

# This parser is one crazy state machine.
# It takes in lines, tries to match them against various regexes to see what they are,
# and updates Games accordingly.
class Parser
  module State
    # No game. Reached if:
    # Game is completed (RES_LIST_LINE, normally from WAITING_RES_LINE)
    # Game is reset (RESET_LINE)
    IDLE = 0

    # Started, waiting for either Avalon line or order line. Reached if:
    # Game starts (START_LINE, normally from IDLE)
    STARTED_ANY = 1

    # Started and have Avalon line, waiting for order line. Reached if:
    # Avalon game starts (AVALON_LINE, normally from STARTED_ANY)
    STARTED_AVALON = 2

    # In progress. Reached if:
    # Player order received (ORDER_LINE, normally from STARTED_*)
    IN_PROGRESS = 3

    # Assassination.
    # In old logs, the next line will be a spy reveal (moving us to the below state.)
    # In new logs, the next line will be an assassination result (win/lose) line.
    # Reached if:
    # Assassination starts (ASSASSIN_START_LINE, normally from IN_PROGRESS)
    ASSASSINATION = 4

    # Assassination where all spies have been revealed (legacy). Reached if:
    # Spies revealed (SPIES_LIST_LINE, normally from ASSASSINATION)
    ASSASSINATION_REVEALED = 5

    # After receiving an assassination result line, (ASSASSIN_{WIN,LOSE}_LINE):
    # For new logs (ASSASSINATION) we expect a spy reveal.
    # For old logs (ASSASSINATION_REVEALED) we expect a res reveal.

    # We're waiting for the line that says "The spies were: ". Reached if:
    # Someone wins on missions ({SPY,RES}_WIN_LINE, normally from IN_PROGRESS)
    # Assassination result from non-legacy assassination (ASSASSIN_{WIN,LOSE}_LINE, only from ASSASSINATION)
    WAITING_SPY_LINE = 6

    # We're waiting for the line that says "The resistance were: ". Reached if:
    # Spies listed (SPIES_LIST_LINE, normally from WAITING_SPY_LINE)
    # Assassination result from legacy assassination (ASSASSIN_{WIN,LOSE}_LINE, only from ASSASSINATION_REVEALED)
    WAITING_RES_LINE = 7
  end

  # TODO: When playing a base game + Avalon variants (lady, excal), ResBot won't put the variants in this line.
  # It WILL, however, send separate VARIANT: lines for those variants.
  # If we ever care about what variants are in the base games, we should take a look at parsing that.
  START_LINE = /^The game has started. There are (\d+) players, with (\d+) spies\./
  # "Using variants" was added in March 2013 or thereabouts - earlier logs won't have it.
  # But we really want to correctly identify Avalon games nevertheless.
  AVALON_LINE = /^This is Resistance: Avalon, with (.*)\.(?: Using variants:(.*))?$/
  ORDER_LINE = /^Player order is: (.*)$/
  SCORE_LINE = /^(O|X)(?: (O|X))?(?: (O|X))?(?: (O|X))?(?: (O|X))?$/
  RESET_LINE = /^The game has been reset\.$/

  SPY_WIN_LINE = /^Game is over! The spies have won!$/
  RES_WIN_LINE = /^Game is over! The resistance wins!$/

  ASSASSIN_START_LINE = /^The resistance successfully completed the missions, but the spies still have a chance\.$/
  # For old-style logs where spies were revealed at assassination time
  ASSASSIN_LIST_LINE = /^The spies are: (.*)\. Assassin, choose a resistance member to assassinate\.$/
  ASSASSIN_WIN_LINE = /^The assassin kills (.*)\. The spies have killed Merlin! Spies win the game!$/
  ASSASSIN_LOSE_LINE = /^The assassin kills (.*)\. The spies have NOT killed Merlin\. Resistance wins!$/

  SPIES_LIST_LINE = /^The spies were: (.*)$/
  RES_LIST_LINE = /^The resistance were: (.*)$/

  attr_reader :games

  def initialize
    @games = []
    @current_game = nil
    @state = State::IDLE
    @log_level = :warn
  end

  def parse(text, time)
    if m = START_LINE.match(text)
      warn('Game start but not idle - last game probably incomplete', time) if @state != State::IDLE
      new_game(time, num_players: m[1].to_i, num_spies: m[2].to_i)
      @state = State::STARTED_ANY

    elsif m = AVALON_LINE.match(text)
      if @state != State::STARTED_ANY
        warn('Avalon line but not started - making new game')
        new_game(time)
      end
      @current_game.avalon!(roles: m[1].split(', '), variants: m[2] ? m[2].split(', ') : [])
      @state = State::STARTED_AVALON

    elsif m = ORDER_LINE.match(text)
      if @state != State::STARTED_ANY && @state != State::STARTED_AVALON
        warn('Order line but not started - making new game', time)
        new_game(time)
      end
      @current_game.order = m[1].split
      @state = State::IN_PROGRESS

    elsif m = SCORE_LINE.match(text)
      if @state != State::IN_PROGRESS
        warn('Score line but not inprogress - making new game', time)
        new_game(time)
        @state = State::IN_PROGRESS
      end
      @current_game.mission_success = text.split.map { |x| x == ?O }

    elsif m = SPY_WIN_LINE.match(text)
      if @state != State::IN_PROGRESS
        warn('Spy win but not inprogress - making new game', time)
        new_game(time)
      end
      @current_game.win_on_missions(:spies, Time.parse(time))
      @state = State::WAITING_SPY_LINE

    elsif m = RES_WIN_LINE.match(text)
      if @state != State::IN_PROGRESS
        warn('Res win but not inprogress - making new game', time)
        new_game(time)
      end
      @current_game.win_on_missions(:resistance, Time.parse(time))
      @state = State::WAITING_SPY_LINE

    elsif m = ASSASSIN_START_LINE.match(text)
      if @state != State::IN_PROGRESS
        warn('Assassin but not inprogress - making new game', time)
        new_game(time)
      end
      @current_game.begin_assassination(Time.parse(time))
      @state = State::ASSASSINATION

    elsif m = ASSASSIN_LIST_LINE.match(text)
      if @state != State::ASSASSINATION
        # This could not have occurred from a !reset,
        # so might as well just make a new game.
        warn('Assassin list but not assassination - making new game', time)
        new_game(time)
      end
      @current_game.spies = m[1]
      @state = State::ASSASSINATION_REVEALED

    elsif m = ASSASSIN_WIN_LINE.match(text)
      if @state == State::ASSASSINATION
        @state = State::WAITING_SPY_LINE
      elsif @state == State::ASSASSINATION_REVEALED
        @state = State::WAITING_RES_LINE
      else
        warn('Target but not assassination - making new game', time)
        new_game(time)
      end

      @current_game.assassinate!(m[1], Time.parse(time), winner: :spies)

    elsif m = ASSASSIN_LOSE_LINE.match(text)
      if @state == State::ASSASSINATION
        @state = State::WAITING_SPY_LINE
      elsif @state == State::ASSASSINATION_REVEALED
        @state = State::WAITING_RES_LINE
      else
        warn('Target but not assassination - making new game', time)
        new_game(time)
      end

      @current_game.assassinate!(m[1], Time.parse(time), winner: :resistance)

    elsif m = SPIES_LIST_LINE.match(text)
      if @state != State::WAITING_SPY_LINE
        if @current_game.spy_players.empty?
          # Rationale: If !reset, spy list is empty. Go and populate it.
          info('Spy list unexpected - reset suspected', time)
        else
          # Otherwise, I just missed some text. Make a new game.
          warn('Spy list unexpected - making new game', time)
          new_game(time)
        end
      end

      @current_game.spies = m[1]
      @state = State::WAITING_RES_LINE

    elsif m = RES_LIST_LINE.match(text)
      if @state != State::WAITING_RES_LINE
        # This cannot happen from !reset (Spy list must come first)
        # HOWEVER, it can occur from the games where spies did not get listed in assassination!
        if @current_game.resistance_players.empty?
          warn('Res list unexpected - spy list needs to be reconstructed', time)
          # TODO actually reconstruct
        else
          warn('Res list unexpected - making new game', time)
          new_game(time)
        end
      end

      @current_game.resistance = m[1]
      @state = State::IDLE

    elsif m = RESET_LINE.match(text)
      @state = State::IDLE
    end
  end

  private

  def log(color, level, msg, time)
    puts "\e[1;#{color}m[#{level}]\e[0m @ #{time}: #{msg}"
  end

  def info(msg, time)
    return unless @log_level == :info
    log(34, 'INFO', msg, time)
  end

  def warn(msg, time)
    log(31, 'WARN', msg, time)
  end

  def new_game(time, num_players: nil, num_spies: nil)
    game = Game.new(Time.parse(time), num_players, num_spies)
    @current_game = game
    @games << game
  end
end

