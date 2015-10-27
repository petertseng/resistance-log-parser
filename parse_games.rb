require 'time'

require_relative 'parser'
require_relative 'player'

# This is the format of one log line.
# First capture group is the time, second capture group is text.
# Only log lines said by ResistanceBot are considered.
# (For now we don't log what players said during the game)
TEXT_LINE = /^(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d) <[@+]?\s+resistancebot_?> (.*)$/i

parser = Parser.new

# If it's a valid path to a file, it's a filename, else it's a player.
filenames, players = ARGV.partition { |x| File.exist?(x) }

filenames.each { |filename|
  File.open(filename, ?r).each_line.grep(TEXT_LINE) { |line|
    time = Regexp.last_match(1)
    text = Regexp.last_match(2)

    parser.parse(text, time)
  }
}

games = parser.games

puts "#{games.size} games"

#ignore reset games
games.select!(&:winning_side)
puts "#{games.size} non-reset games"
puts

longest_game = games.max_by(&:duration)
puts "Longest game: #{longest_game} from #{longest_game.start_time} to #{longest_game.end_time} lasting #{longest_game.duration / 60.0} mins"
puts

longest_assassination_game = games.max_by(&:assassination_duration)
puts "Longest assassination game: #{longest_assassination_game} from #{longest_assassination_game.mission_end_time} to #{longest_assassination_game.assassination_end_time} lasting #{longest_assassination_game.assassination_duration / 60.0} mins"
puts

# Global stats
def game_stats(games)
  av_games, base_games = games.partition(&:avalon?)

  base_res_win = base_games.count { |x| x.winning_side == :resistance }
  base_spy_win = base_games.count { |x| x.winning_side == :spies }

  av_res_win = av_games.count { |x| x.winning_side == :resistance }
  av_spy_mission = av_games.count { |x| x.winning_side == :spies && !x.assassin_target }
  av_spy_assassinate = av_games.count { |x| x.winning_side == :spies && x.assassin_target }

  <<-STATS.gsub(/^  /, '')
  #{base_games.size} base games. #{base_res_win} res wins. #{base_spy_win} spy wins.
  #{av_games.size} Avalon games. #{av_res_win} res wins. #{av_spy_mission} spy wins (mission). #{av_spy_assassinate} spy wins (assassination).
  STATS
end

# categories should be an Hash where each key is a description,
# and the corresponding value is a one-argument block.
# The block returns true if the game counts for that category.
def categorize_games(games, categories)
  categories.map { |desc, block| "#{desc} #{games.count(&block)} games" }
end

def player_stats(games, name)
  lines = ["Stats for #{name}"]
  av_games, base_games = games.partition(&:avalon?)

  base_res = base_games.select { |x| x.resistance_players.include?(name) }
  base_spy = base_games.select { |x| x.spy_players.include?(name) }
  base_res_win = base_res.count { |x| x.winning_side == :resistance }
  base_spy_win = base_spy.count { |x| x.winning_side == :spies }

  lines << "BASE: As res, won #{base_res_win}/#{base_res.size} games. As spy, won #{base_spy_win}/#{base_spy.size} games."

  av_res = av_games.select { |x| x.resistance_players.include?(name) }
  merlin, nonmerlin = av_res.partition { |x| x.roles[name] == 'Merlin' }
  av_res_win = av_res.count { |x| x.winning_side == :resistance }

  av_spy = av_games.select { |x| x.spy_players.include?(name) }
  av_spy_win = av_spy.count { |x| x.winning_side == :spies }

  lines << "AVALON: As res, won #{av_res_win}/#{av_res.size} games. As spy, won #{av_spy_win}/#{av_spy.size} games."

  merlin_stats = categorize_games(merlin, {
    'Won' => ->(x) { x.winning_side == :resistance },
    'died' => ->(x) { x.assassin_target == name},
    'let spies win missions' => ->(x) { x.spy_score == 3 },
    'rejected hammer' => :hammer_rejected?,
  }).join(', ')
  lines << "AS MERLIN (#{merlin.size} games): #{merlin_stats}"

  nonmerlin_stats = categorize_games(nonmerlin, {
    'Got killed (win)' => ->(x) { x.assassin_target == name },
    'other Non-Merlin got killed (win)' => ->(x) { x.assassin_target != name && x.winning_side == :resistance },
    'let Merlin die' => ->(x) { x.res_score == 3 && x.winning_side == :spies },
    'let spies win missions' => ->(x) { x.spy_score == 3 },
    'rejected hammer' => :hammer_rejected?,
  }).join(', ')
  lines << "AS NON-MERLIN RES (#{nonmerlin.size} games): #{nonmerlin_stats}"

  av_spy_stats = categorize_games(av_spy, {
    'Won on missions' => ->(x) { x.spy_score == 3 },
    'killed Merlin' => ->(x) { x.res_score == 3 && x.winning_side == :spies },
    'rejected hammer' => :hammer_rejected?,
    'lost' => ->(x) { x.res_score == 3 && x.winning_side == :resistance },
  }).join(', ')
  lines << "AS SPY (#{av_spy.size} games): #{av_spy_stats}"

  lines
end

base_players = Hash.new { |h, k| h[k] = Player.new(k) }
avalon_players = Hash.new { |h, k| h[k] = Player.new(k) }
all_players = Hash.new { |h, k| h[k] = Player.new(k) }

games.each { |g|
  hs = g.avalon? ? [avalon_players, all_players] : [base_players, all_players]
  hs.each { |h|
    g.resistance_players.each { |p| h[p].play_res(win: g.winning_side == :resistance) }
    g.spy_players.each { |p| h[p].play_spy(win: g.winning_side == :spies) }
  }
}

sides = {
  'rebels' => :res,
  'spies' => :spy,
}
game_types = {
  'base' => base_players.values,
  'avalon' => avalon_players.values,
}

def leaderboard(players, side_sym)
  players.select(&:"#{side_sym}_significant?").sort_by(&:"#{side_sym}_winrate").reverse.map { |x| x.to_s(type: side_sym) }
end

game_types.each { |type, type_players|
  sides.each { |side_name, side_sym|
    puts "best #{type} #{side_name}".upcase
    puts leaderboard(type_players, side_sym)
    puts
  }
}

sides.each { |side_name, side_sym|
  puts "best #{side_name}".upcase
  puts leaderboard(all_players.values, side_sym)
  puts
}

puts 'GLOBAL STATS'
puts game_stats(games)
puts

puts 'STATS FOR M1 FAILS'
puts game_stats(games.select { |x| !x.mission_success[0] })
puts

puts players.map { |p| player_stats(games, p).join("\n") }.join("\n\n")
