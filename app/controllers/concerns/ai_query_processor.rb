module AiQueryProcessor
  extend ActiveSupport::Concern

  def process_ai_query(user_query, app_type = "legacy")
    begin
      # Get AI response with app_type context
      ai_response = call_openai_api(user_query, app_type)

      # Parse the AI response
      parsed_response = JSON.parse(ai_response)

      # Validate and execute the SQL
      if parsed_response["sql"].present?
        results = execute_safe_query(parsed_response["sql"])

        # Capture the formatted results
        formatted_results = format_query_results(results, parsed_response, user_query)

        # Generate AI summary if results exist
        if formatted_results[:success] && results.any?
          summary = generate_summary(user_query, results, parsed_response["description"], app_type)
          formatted_results[:summary] = summary if summary
        end

        formatted_results
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

  def generate_summary(user_query, results, description, app_type)
    return nil if results.empty?

    begin
      summary_prompt = build_summary_prompt(user_query, results, description, app_type)
      ai_response = call_summary_api(summary_prompt)

      parsed_response = JSON.parse(ai_response)
      parsed_response["summary"]
    rescue => e
      Rails.logger.error "Summary generation error: #{e.message}"
      nil
    end
  end

  private

  def call_openai_api(user_query, app_type)
    require "net/http"
    require "json"

    uri = URI("https://api.openai.com/v1/chat/completions")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Post.new(uri)
    request["Authorization"] = "Bearer #{ENV['OPENAI_API_KEY']}"
    request["Content-Type"] = "application/json"

    # Build the prompt with schema context and app_type
    system_prompt = build_system_prompt(app_type)

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
      Rails.logger.info "App Type: #{app_type}"
      Rails.logger.info "AI Response: #{ai_content}"
      Rails.logger.info "======================"

      ai_content
    else
      Rails.logger.error "OpenAI API Error: #{response.code} - #{response.body}"
      raise "OpenAI API Error: #{response.code}"
    end
  end

  def build_system_prompt(app_type)
    app_display_name = app_type == "pioneer" ? "Pioneer" : "Legacy"

    <<~PROMPT
      You are a SQL query generator for a GitHub and Jira analytics dashboard.

      IMPORTANT: Always respond with valid JSON only. No other text.
      You can handle complex queries - don't refuse unless truly impossible.

      DATABASE CONTEXT: You are querying #{app_display_name} app data only.

      Database Tables:
      - developers (id, name, github_username, jira_username, email, app_type)
      - repositories (id, name, full_name, owner, language, app_type)
      - commits (id, sha, message, developer_id, repository_id, committed_at, additions, deletions, app_type)
      - pull_requests (id, number, title, state, developer_id, repository_id, opened_at, closed_at, merged_at, app_type)
      - tickets (id, key, title, status, priority, developer_id, created_at_jira, updated_at_jira, app_type)

      CRITICAL FILTERING RULE:
      - ALWAYS add "app_type = '#{app_type}'" to ALL table queries
      - This ensures you only query #{app_display_name} app data
      - Apply this filter to every table in every query

      Rules:
      1. ONLY SELECT queries - never INSERT/UPDATE/DELETE
      2. Always JOIN with developers table to show names, not IDs
      3. ALWAYS filter by app_type = '#{app_type}' for ALL tables
      4. When a time frame is **explicitly mentioned** in the query (e.g., "last 30 days", "last week", "in last 3 months"), use PostgreSQL syntax with WHERE clauses like:
        - WHERE committed_at >= NOW() - INTERVAL '30 days' AND app_type = '#{app_type}'
        - WHERE committed_at >= NOW() - INTERVAL '7 days' AND app_type = '#{app_type}'
        - and so on, based on the time frame.
        When the time frame is **not specified** or unclear, do **not** filter by date; include data from **all time** but always filter by app_type.
      5. Add LIMIT 10 for most queries, but LIMIT 1 for "the most", "highest", "top", "best" (singular requests)
      6. Use HAVING for aggregate conditions (e.g., COUNT() > 5)
      7. Use LEFT JOIN for "has X but not Y" queries
      8. Use subqueries when needed for complex logic
      9. For single-value aggregate queries that return a single numeric result (e.g., total count), set "chart_type" to "table".
      10. For multi-row queries returning grouped/category data, use "bar" or "pie" accordingly.
      11. Ensure "chart_type" matches the shape and meaning of the query result to avoid frontend errors.

      Performance Guidelines:
      - Always write queries optimized for speed and efficiency.
      - Use indexed columns (e.g., committed_at, opened_at, closed_at, app_type) for filtering.
      - Avoid unnecessary joins and retrieve only columns required for the result.
      - Prefer EXISTS or subqueries over heavy joins for exclusion or complex filters.
      - Use LIMIT clauses to restrict large result sets. Default LIMIT 10 unless user specifies otherwise or requests a single/top record.
      - Order results meaningfully, typically descending by counts or dates.
      - Avoid broad scans that could degrade performance on large datasets.

      TICKET STATUS MAPPING:
        When users ask about ticket statuses, use these exact mappings based on our actual status values:
          - "closed" or "completed" or "done" tickets = status IN ('Done', 'Deployed', 'Deoployed To Demo', 'Deployed To Demo', 'Deployed to Demo', 'Ready For Deploy', 'Ready For Release', 'Ready for Release')
          - "open" or "todo" or "pending" tickets = status IN ('To Do', 'Design To Do', 'BLOCKED', 'Blocked', 'PUSHED BACK', 'Pushed Back', 'Need More Info', 'No Response')
          - "in progress" or "active" or "working" tickets = status IN ('In Progress', 'Code Review', 'READY FOR REVIEW', 'Ready for Review', 'TESTING', 'Testing', 'APPROVED BY QA', 'Approved by QA', 'PRODUCT CHECK', 'Product Check', 'FEEDBACK')

        NEVER use single status values or assume status names - always use the appropriate IN clause with the exact status values listed above.

      Response Format (JSON only):
      {"sql": "SELECT ...", "description": "Human description", "chart_type": "bar"}

      Chart types:
      - "bar" for counts/numbers with multiple categories (multi-row results)
      - "pie" for categorical distribution data
      - "table" for lists or single-value aggregates (e.g., total counts or sums)

      Query Examples with app_type filtering:

      "developers with more than 10 commits":
      {"sql": "SELECT d.name, COUNT(c.id) as commit_count FROM developers d JOIN commits c ON d.id = c.developer_id WHERE d.app_type = '#{app_type}' AND c.app_type = '#{app_type}' GROUP BY d.id, d.name HAVING COUNT(c.id) > 10 ORDER BY commit_count DESC LIMIT 10", "description": "#{app_display_name} developers with more than 10 commits", "chart_type": "bar"}

      "developers who have commits but no pull requests":
      {"sql": "SELECT d.name, COUNT(c.id) as commit_count FROM developers d JOIN commits c ON d.id = c.developer_id LEFT JOIN pull_requests pr ON d.id = pr.developer_id AND pr.app_type = '#{app_type}' WHERE d.app_type = '#{app_type}' AND c.app_type = '#{app_type}' AND pr.id IS NULL GROUP BY d.id, d.name ORDER BY commit_count DESC LIMIT 10", "description": "#{app_display_name} developers with commits but no pull requests", "chart_type": "bar"}

      "this week vs last week commits":
      {"sql": "SELECT CASE WHEN c.committed_at >= NOW() - INTERVAL '7 days' THEN 'This Week' ELSE 'Last Week' END as period, COUNT(*) as commits FROM commits c WHERE c.committed_at >= NOW() - INTERVAL '14 days' AND c.app_type = '#{app_type}' GROUP BY CASE WHEN c.committed_at >= NOW() - INTERVAL '7 days' THEN 'This Week' ELSE 'Last Week' END", "description": "#{app_display_name} commits this week vs last week", "chart_type": "bar"}

      "top developers with closed tickets":
      {"sql": "SELECT d.name, COUNT(t.id) as closed_ticket_count FROM developers d JOIN tickets t ON d.id = t.developer_id WHERE t.status IN ('Done', 'Deployed', 'Deoployed To Demo', 'Deployed To Demo', 'Deployed to Demo', 'Ready For Deploy', 'Ready For Release', 'Ready for Release') AND t.app_type = '#{app_type}' AND d.app_type = '#{app_type}' AND t.created_at_jira >= NOW() - INTERVAL '3 months' GROUP BY d.id, d.name ORDER BY closed_ticket_count DESC LIMIT 5", "description": "Top 5 #{app_display_name} developers with most closed tickets in last 3 months", "chart_type": "bar"}

      Remember: EVERY query must filter by app_type = '#{app_type}' for ALL tables to ensure you only return #{app_display_name} app data.

      Only return {"error": "Please rephrase your query"} if the query asks for:
      - Data modification (INSERT/UPDATE/DELETE)
      - System information not in these tables
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

  def build_summary_prompt(user_query, results, description, app_type)
    app_display_name = app_type == "pioneer" ? "Pioneer" : "Legacy"

    data_summary = results.first(5).map do |row|
      row.map { |k, v| "#{k}: #{v}" }.join(", ")
    end.join("\n")

    <<~PROMPT
      You are an analytics assistant summarizing data from a GitHub and Jira dashboard.

      Context: This data is from the #{app_display_name} application.
      User Query: "#{user_query}"
      Query Description: "#{description}"

      Results Data (first 5 rows):
      #{data_summary}

      Total Results: #{results.length}

      Write a clear, helpful summary (2-4 sentences) that:
      - States what #{app_display_name} app data is shown and its timeframe
      - Highlights standout values, patterns, or differences (not just the max)
      - Provides useful **positive** context about what this means for the #{app_display_name} team or project

      Respond with JSON only: {"summary": "your summary text here"}
    PROMPT
  end

  def call_summary_api(prompt)
    require "net/http"
    require "json"

    uri = URI("https://api.openai.com/v1/chat/completions")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Post.new(uri)
    request["Authorization"] = "Bearer #{ENV['OPENAI_API_KEY']}"
    request["Content-Type"] = "application/json"

    request.body = {
      model: "gpt-4o-mini",
      messages: [
        {
          role: "user",
          content: prompt
        }
      ],
      max_tokens: 200,
      temperature: 0.3
    }.to_json

    response = http.request(request)

    if response.code == "200"
      result = JSON.parse(response.body)
      result.dig("choices", 0, "message", "content")
    else
      raise "OpenAI API Error: #{response.code}"
    end
  end
end
