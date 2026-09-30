require_relative 'support/code_quality'

findings = GameRoomQuality.findings
baseline = JSON.parse(File.read(GameRoomQuality::BASELINE))
failures = GameRoomQuality.new_findings(findings, baseline)
failures.each { |item| warn "#{item[:file]}:#{item[:line]} #{item[:rule]} #{item[:detail]}" }
raise "#{failures.length} new code-quality findings" unless failures.empty?
puts "PASS code quality: #{findings.length} existing findings, no growth beyond the reviewed baseline"
