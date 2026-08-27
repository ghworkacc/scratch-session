require "csv"

ARGV.first || abort("Usage: ruby show_error_reason.rb errors.csv")

file_name = ARGV.first

counts = Hash.new(0)

# Fields are wrapped in single quotes and may contain embedded commas,
# so parse with a single-quote quote character.
CSV.foreach(file_name, quote_char: "'", liberal_parsing: true) do |row|
  reason = row[2]
  next if reason.nil?

  reason = reason.strip.gsub(/\A'|'\z/, "").strip
  next if reason.empty?
  next if reason == "message" # skip header

  counts[reason] += 1
end

counts.sort_by { |_reason, count| -count }.each do |reason, count|
  puts "#{count}\t#{reason}"
end
