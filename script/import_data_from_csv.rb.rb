require 'csv'

csv_file = ENV['CSV_PATH'] || Rails.root.join('lib', 'data', 'jira_data_dump.csv')

created = 0
updated = 0
skipped = 0
errors = []

def parse_date(date_str)
  return nil if date_str.nil? || date_str.strip.empty?

  # date formats like "16/Oct/25 7:35 PM" -> parse day/Mon/yy
  date_part = date_str.split(' ').first
  Date.strptime(date_part, '%d/%b/%y')
rescue ArgumentError
  warn "⚠️  Could not parse date: #{date_str}"
  nil
end

unless File.exist?(csv_file)
  puts "CSV file not found: #{csv_file}"
  exit 1
end

puts "Importing CSV: #{csv_file}"

row_count = 0
CSV.foreach(csv_file, headers: true, encoding: 'UTF-8') do |row|
  row_count += 1
  begin
    next if row['Issue key'].nil? || row['Issue key'].strip.empty?

    issue_key = row['Issue key'].strip
    jira_id = row['Issue id']&.strip
    project_key = issue_key.split('-').first

    developer = nil
    if row['Assignee'].present?
      assignee_name = row['Assignee'].strip

      developer = Developer.find_by(
        "LOWER(name) = ? AND app_type = ?",
        assignee_name.downcase,
        'pioneer'
      )

      unless developer
        developer = Developer.where(app_type: 'pioneer')
                             .where("LOWER(name) LIKE ?", "%#{assignee_name.downcase}%")
                             .first
      end

      puts "Developer not found for assignee: #{assignee_name} (#{issue_key})" if developer.nil?
    end

    ticket = Ticket.find_by(key: issue_key) || (jira_id.present? && Ticket.find_by(jira_id: jira_id))

    is_new = ticket.nil?
    ticket ||= Ticket.new

    ticket.assign_attributes(
      key: issue_key,
      title: row['Summary']&.strip,
      description: nil,
      status: row['Status']&.strip,
      priority: row['Priority']&.strip,
      ticket_type: row['Issue Type']&.strip,
      developer_id: developer&.id,
      project_key: project_key,
      jira_id: jira_id,
      created_at_jira: parse_date(row['Created']),
      updated_at_jira: parse_date(row['Updated']),
      app_type: 'pioneer'
    )

    if ticket.save
      if is_new
        created += 1
        print '+'
      else
        updated += 1
        print '.'
      end
    else
      skipped += 1
      errors << "#{issue_key}: #{ticket.errors.full_messages.join(', ')}"
      print 'x'
    end
  rescue => e
    skipped += 1
    errors << "Row error (#{row['Issue key'] rescue 'N/A'}): #{e.message}"
    print 'E'
  end
end

puts "Import complete!"
puts "=" * 60
puts "Created:  #{created} new tickets"
puts "Updated:  #{updated} existing tickets"
puts "Skipped:  #{skipped} tickets"
puts "Total:    #{created + updated + skipped} processed"

if errors.any?
  puts "Errors encountered (showing first 20):"
  errors.first(20).each_with_index do |err, i|
    puts "  #{i + 1}. #{err}"
  end
  puts "  ... and #{errors.size - 20} more errors" if errors.size > 20
end

puts "Statistics:"

puts "Tickets by status:"
Ticket.where(app_type: 'pioneer').group(:status).count.each do |status, count|
  puts "  #{status}: #{count}"
end

puts "Tickets by type:"
Ticket.where(app_type: 'pioneer').group(:ticket_type).count.each do |type, count|
  puts "  #{type}: #{count}"
end

puts "Top 5 developers by ticket count:"
Ticket.where(app_type: 'pioneer')
      .joins(:developer)
      .group('developers.name')
      .count
      .sort_by { |_, count| -count }
      .first(5)
      .each do |name, count|
  puts "  #{name}: #{count} tickets"
end