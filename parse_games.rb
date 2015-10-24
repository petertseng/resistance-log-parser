require 'time'

require_relative 'parser'

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
puts "Longest game: #{longest_game} with #{longest_game.duration}"
puts

longest_assassination_game = games.max_by(&:assassination_duration)
puts "Longest assassination game: #{longest_assassination_game} with #{longest_assassination_game.assassination_duration}"
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

  merlin_win = merlin.count { |x| x.winning_side == :resistance }
  merlin_dead = merlin.count { |x| x.assassin_target == name }
  merlin_fail = merlin.count { |x| x.spy_score == 3 }
  lines << "AS MERLIN (#{merlin.size} games): Won #{merlin_win} games, died #{merlin_dead} games, let spies win missions #{merlin_fail} games"

  nonmerlin_dead = nonmerlin.count { |x| x.assassin_target == name }
  nonmerlin_win = nonmerlin.count { |x| x.assassin_target != name && x.winning_side == :resistance }
  nonmerlin_merlin_died = nonmerlin.count { |x| x.res_score == 3 && x.winning_side == :spies }
  nonmerlin_missions = nonmerlin.count { |x| x.spy_score == 3 }
  lines << "AS NON-MERLIN RES (#{nonmerlin.size} games): Got killed (win) #{nonmerlin_dead} games, other Non-Merlin got killed (win) #{nonmerlin_win} games, let Merlin die #{nonmerlin_merlin_died} games, let spies win missions #{nonmerlin_missions} games"

  av_spy_mission = av_spy.count { |x| x.spy_score == 3 }
  av_spy_assassination = av_spy.count { |x| x.res_score == 3 && x.winning_side == :spies }
  av_spy_loss = av_spy.count { |x| x.res_score == 3 && x.winning_side == :resistance }
  lines << "AS SPY (#{av_spy.size} games): Won on missions #{av_spy_mission} games, killed Merlin #{av_spy_assassination} games, lost #{av_spy_loss} games"

  lines
end

puts 'GLOBAL STATS'
puts game_stats(games)
puts

puts 'STATS FOR M1 FAILS'
puts game_stats(games.select { |x| !x.mission_success[0] })
puts

puts players.map { |p| player_stats(games, p).join("\n") }.join("\n\n")
