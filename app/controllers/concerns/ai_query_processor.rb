module AiQueryProcessor
  extend ActiveSupport::Concern

  def process_ai_query(user_query)
    begin
      # Get AI response
      ai_response = call_openai_api(user_query)

      # Parse the AI response
      parsed_response = JSON.parse(ai_response)

      # Validate and execute the SQL
      if parsed_response["sql"].present?
        results = execute_safe_query(parsed_response["sql"])

        # Format results for frontend
        format_query_results(results, parsed_response, user_query)
      else
        { error: "Could not generate a valid query from your request." }
      end

    rescue JSON::ParserError
      { error: "Invalid response from AI service." }
    rescue => e
      Rails.logger.error "AI Query Error: #{e.message}"
      { error: "Sorry, I couldn't process your query. Please try rephrasing it." }
    end
  end

  private

  def call_openai_api(user_query)
    require "net/http"
    require "json"

    uri = URI("https://api.openai.com/v1/chat/completions")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Post.new(uri)
    request["Authorization"] = "Bearer #{ENV['OPENAI_API_KEY']}"
    request["Content-Type"] = "application/json"

    # Build the prompt with schema context
    system_prompt = build_system_prompt

    request.body = {
      model: "gpt-4o-mini",
      messages: [
        {
          role: "system",
          content: system_prompt
        },
        {
          role: "user",
          content: user_query
        }
      ],
      max_tokens: 800,
      temperature: 0.1
    }.to_json

    response = http.request(request)

    if response.code == "200"
      result = JSON.parse(response.body)
      ai_content = result.dig("choices", 0, "message", "content")

      # Add logging to see what AI returns
      Rails.logger.info "=== AI QUERY DEBUG ==="
      Rails.logger.info "User Query: #{user_query}"
      Rails.logger.info "AI Response: #{ai_content}"
      Rails.logger.info "======================"

      ai_content
    else
      Rails.logger.error "OpenAI API Error: #{response.code} - #{response.body}"
      raise "OpenAI API Error: #{response.code}"
    end
  end

  def build_system_prompt
    <<~PROMPT
      You are a SQL query generator for a GitHub and Jira analytics dashboard.

      IMPORTANT: Always respond with valid JSON only. No other text.
      You can handle complex queries - don't refuse unless truly impossible.

      Database Tables:
      - developers (id, name, github_username, jira_username, email)
      - repositories (id, name, full_name, owner, language)
      - commits (id, sha, message, developer_id, repository_id, committed_at, additions, deletions)
      - pull_requests (id, number, title, state, developer_id, repository_id, opened_at, closed_at, merged_at)
      - tickets (id, key, title, status, priority, developer_id, created_at_jira, updated_at_jira)

      Rules:
      1. ONLY SELECT queries - never INSERT/UPDATE/DELETE
      2. Always JOIN with developers table to show names, not IDs
      3. Use PostgreSQL syntax: WHERE committed_at >= NOW() - INTERVAL '30 days'
      4. Add LIMIT 10 for most queries, but LIMIT 1 for "the most", "highest", "top", "best" (singular requests)
      5. Use HAVING for aggregate conditions (e.g., COUNT() > 5)
      6. Use LEFT JOIN for "has X but not Y" queries
      7. Use subqueries when needed for complex logic

      Response Format (JSON only):
      {"sql": "SELECT ...", "description": "Human description", "chart_type": "bar"}

      Chart types: "bar" for counts/numbers, "pie" for categories, "table" for lists

      Complex Query Examples:

      "developers with more than 10 commits":
      {"sql": "SELECT d.name, COUNT(c.id) as commit_count FROM developers d JOIN commits c ON d.id = c.developer_id GROUP BY d.id, d.name HAVING COUNT(c.id) > 10 ORDER BY commit_count DESC LIMIT 10", "description": "Developers with more than 10 commits", "chart_type": "bar"}

      "developers who have commits but no pull requests":
      {"sql": "SELECT d.name, COUNT(c.id) as commit_count FROM developers d JOIN commits c ON d.id = c.developer_id LEFT JOIN pull_requests pr ON d.id = pr.developer_id WHERE pr.id IS NULL GROUP BY d.id, d.name ORDER BY commit_count DESC LIMIT 10", "description": "Developers with commits but no pull requests", "chart_type": "bar"}

      "repositories with more than 5 commits":
      {"sql": "SELECT r.name, COUNT(c.id) as commit_count, COUNT(DISTINCT c.developer_id) as developer_count FROM repositories r JOIN commits c ON r.id = c.repository_id GROUP BY r.id, r.name HAVING COUNT(c.id) > 5 ORDER BY commit_count DESC LIMIT 10", "description": "Repositories with more than 5 commits", "chart_type": "bar"}

      "average commit size by developer":
      {"sql": "SELECT d.name, AVG(c.additions + c.deletions) as avg_lines_changed FROM developers d JOIN commits c ON d.id = c.developer_id GROUP BY d.id, d.name ORDER BY avg_lines_changed DESC LIMIT 10", "description": "Average lines changed per commit by developer", "chart_type": "bar"}

      "repositories by programming language":
      {"sql": "SELECT r.language, COUNT(*) as repo_count FROM repositories r WHERE r.language IS NOT NULL GROUP BY r.language ORDER BY repo_count DESC LIMIT 10", "description": "Repositories grouped by programming language", "chart_type": "pie"}

      Time comparisons:
      "this week vs last week commits":
      {"sql": "SELECT CASE WHEN c.committed_at >= NOW() - INTERVAL '7 days' THEN 'This Week' ELSE 'Last Week' END as period, COUNT(*) as commits FROM commits c WHERE c.committed_at >= NOW() - INTERVAL '14 days' GROUP BY CASE WHEN c.committed_at >= NOW() - INTERVAL '7 days' THEN 'This Week' ELSE 'Last Week' END", "description": "Commits this week vs last week", "chart_type": "bar"}

      "this week vs last month":
      {"sql": "SELECT CASE WHEN c.committed_at >= NOW() - INTERVAL '7 days' THEN 'This Week' WHEN c.committed_at >= NOW() - INTERVAL '30 days' THEN 'Last Month' END as period, COUNT(*) as commits FROM commits c WHERE c.committed_at >= NOW() - INTERVAL '30 days' GROUP BY period ORDER BY period", "description": "Commits this week vs last month", "chart_type": "bar"}

      Only return {"error": "Please rephrase your query"} if the query asks for:
      - Data modification (INSERT/UPDATE/DELETE)
      - System information not in our tables
      - Truly impossible requests

      Otherwise, attempt to generate SQL for complex queries using JOINs, subqueries, HAVING, etc.
    PROMPT
  end

  def execute_safe_query(sql)
    unless sql.strip.downcase.start_with?("select")
      raise "Only SELECT queries are allowed"
    end

    dangerous_patterns = [
      /\b(drop|delete|insert|alter|create|truncate)\s+/i,
      /;\s*(drop|delete|insert|alter|create|truncate)/i,
      /\bupdate\s+\w+\s+set\b/i,
      /\binto\s+\w+\s*\(/i
    ]

    if dangerous_patterns.any? { |pattern| sql.match?(pattern) }
      raise "Query contains prohibited SQL commands"
    end

    # Execute query with timeout
    ActiveRecord::Base.connection.execute("SET statement_timeout = 10000")
    result = ActiveRecord::Base.connection.exec_query(sql)

    # Convert to array of hashes for easier processing
    result.to_a
  end

  def format_query_results(results, ai_response, user_query)
    return { error: "No results found" } if results.empty?

    chart_type = ai_response["chart_type"] || "table"
    description = ai_response["description"] || "Query Results"

    # Format based on chart type and result structure
    formatted_data = case chart_type
    when "bar"
      format_for_bar_chart(results)
    when "pie"
      format_for_pie_chart(results)
    else
      format_for_table(results)
    end

    {
      success: true,
      user_query: user_query,
      description: description,
      chart_type: chart_type,
      data: formatted_data,
      raw_results: results
    }
  end

  def format_for_bar_chart(results)
    # Assume first column is labels, second is values
    columns = results.first.keys

    if columns.length >= 2
      labels = results.map { |row| row[columns[0]].to_s }
      values = results.map { |row| row[columns[1]].to_i }

      {
        labels: labels,
        datasets: [ {
          label: columns[1].humanize,
          data: values,
          backgroundColor: "rgba(52, 152, 219, 0.6)",
          borderColor: "rgba(52, 152, 219, 1)",
          borderWidth: 1
        } ]
      }
    else
      format_for_table(results)
    end
  end

  def format_for_pie_chart(results)
    columns = results.first.keys

    if columns.length >= 2
      labels = results.map { |row| row[columns[0]].to_s }
      data = results.map { |row| row[columns[1]].to_i }

      colors = [
        "rgba(52, 152, 219, 0.6)",   # Blue
        "rgba(46, 204, 113, 0.6)",   # Green
        "rgba(241, 196, 15, 0.6)",   # Yellow
        "rgba(231, 76, 60, 0.6)",    # Red
        "rgba(155, 89, 182, 0.6)",   # Purple
        "rgba(230, 126, 34, 0.6)"   # Orange
      ]

      {
        labels: labels,
        datasets: [ {
          data: data,
          backgroundColor: colors.cycle.take(data.length),
          borderColor: colors.cycle.take(data.length).map { |c| c.gsub("0.6", "1") },
          borderWidth: 1
        } ]
      }
    else
      format_for_table(results)
    end
  end

  def format_for_table(results)
    {
      headers: results.first&.keys || [],
      rows: results.map(&:values)
    }
  end
end
