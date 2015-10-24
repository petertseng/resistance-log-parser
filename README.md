# resistance-log-parser

This is a parser for IRC logs of [ResistanceBot](https://github.com/caitlin/cinch-resistancegame) games.
It outputs some stats about the games.

# usage

`ruby parse_games.rb logs/* player1 player2` or similar.

As can be seen, pass a list of log files on ARGV, and lines from each log file are read sequentially.
Results are output to standard output.

Additionally, a list of player names can be passed (also on ARGV).
Stats for those players are output to standard output.

An argument is assumed to be a filename if it is a path to a file, otherwise it is assumed to be a player name.
