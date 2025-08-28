module BedrockAiQueryProcessor
  extend ActiveSupport::Concern

  # Single model configuration - using Claude 3.5 Sonnet v2 inference profile
  MODEL_CONFIG = {
    model_id: "us.anthropic.claude-3-5-sonnet-20241022-v2:0",
    max_tokens: 1000,
    temperature: 0.1,
    description: "Claude 3.5 Sonnet v2 - handles all query types from simple to complex"
  }.freeze

  def process_bedrock_ai_query(user_query, app_type = "legacy")
    begin
      Rails.logger.info "=== BEDROCK QUERY PROCESSING ==="
      Rails.logger.info "User Query: #{user_query}"
      Rails.logger.info "App Type: #{app_type}"
      Rails.logger.info "Using Model: #{MODEL_CONFIG[:model_id]}"

      # Get database schema context for better results
      schema_context = get_database_context(app_type)

      # Generate query using Claude 3.5 Sonnet
      ai_response = call_bedrock_api(user_query, app_type, schema_context)

      # Clean and parse the AI response
      parsed_response = parse_ai_response(ai_response)

      # Execute and validate query
      if parsed_response["sql"].present?
        results = execute_safe_query(parsed_response["sql"])

        # If query returns no results, try refinement
        if results.empty?
          Rails.logger.info "Initial query returned no results, attempting refinement..."
          refined_response = refine_query_with_context(user_query, parsed_response["sql"], app_type, schema_context)

          if refined_response && refined_response["sql"].present?
            results = execute_safe_query(refined_response["sql"])
            parsed_response = refined_response if results.any?
          end
        end

        # Format results
        formatted_results = format_query_results(results, parsed_response, user_query)

        # Generate intelligent summary
        if formatted_results[:success] && results.any?
          summary = generate_intelligent_summary(user_query, results, parsed_response["description"], app_type)
          formatted_results[:summary] = summary if summary
        end

        # Add metadata about the processing
        formatted_results[:processing_info] = {
          model_used: MODEL_CONFIG[:model_id],
          refinement_used: refined_response.present?
        }

        formatted_results
      else
        { error: "Could not generate a valid query from your request." }
      end

    rescue JSON::ParserError => e
      Rails.logger.error "JSON Parse Error: #{e.message}"
      { error: "Invalid response from AI service." }
    rescue => e
      Rails.logger.error "Bedrock AI Query Error: #{e.message}"
      { error: "Sorry, I couldn't process your query. Please try rephrasing it." }
    end
  end

  private

  def parse_ai_response(ai_response)
    return {} if ai_response.nil? || ai_response.strip.empty?

    # Clean the response - handle escaped content
    cleaned_response = ai_response.strip

    # Remove surrounding quotes if present
    if cleaned_response.start_with?('"') && cleaned_response.end_with?('"')
      cleaned_response = cleaned_response[1...-1]
    end

    # Handle escaped newlines, quotes, and other escape sequences
    cleaned_response = cleaned_response.gsub('\\n', "\n")
                                     .gsub('\\r', "\r")
                                     .gsub('\\t', "\t")
                                     .gsub('\\"', '"')
                                     .gsub("\\\\", "\\")

    Rails.logger.info "=== PARSING AI RESPONSE ==="
    Rails.logger.info "Attempting to parse JSON..."
    Rails.logger.info "=========================="

    JSON.parse(cleaned_response)
  rescue JSON::ParserError => e
    Rails.logger.error "JSON parsing failed: #{e.message}"

    # Enhanced regex extraction that handles multiline content better
    begin
      # Extract fields with support for multiline content
      if cleaned_response.include?("sql") || cleaned_response.include?("summary") || cleaned_response.include?("description")

        # Try to extract SQL field
        sql_match = cleaned_response.match(/"sql":\s*"((?:[^"\\]|\\[\\"])*)"/m)

        # Try to extract description field
        desc_match = cleaned_response.match(/"description":\s*"((?:[^"\\]|\\[\\"])*)"/m)

        # Try to extract chart_type field
        chart_match = cleaned_response.match(/"chart_type":\s*"((?:[^"\\]|\\[\\"])*)"/m)

        # Try to extract summary field (for summary responses)
        summary_match = cleaned_response.match(/"summary":\s*"((?:[^"\\]|\\[\\"])*)"/m)

        result = {}

        if sql_match
          result["sql"] = sql_match[1].gsub('\\"', '"').gsub("\\\\", "\\")
        end

        if desc_match
          result["description"] = desc_match[1].gsub('\\"', '"').gsub("\\\\", "\\")
        end

        if chart_match
          result["chart_type"] = chart_match[1].gsub('\\"', '"').gsub("\\\\", "\\")
        end

        if summary_match
          result["summary"] = summary_match[1].gsub('\\"', '"').gsub("\\\\", "\\")
        end

        # Return result if we got at least one field
        if result.any?
          Rails.logger.info "Successfully extracted fields using regex: #{result.keys.join(', ')}"
          return result
        end
      end
    rescue => regex_error
      Rails.logger.error "Regex extraction failed: #{regex_error.message}"
    end

    raise JSON::ParserError, "Could not parse AI response: #{e.message}"
  end

  def get_database_context(app_type)
    begin
      # Get actual table schemas and sample data
      context = []

      # Sample recent data to understand current state
      recent_commits = ActiveRecord::Base.connection.execute(
        "SELECT COUNT(*) as total, MAX(committed_at) as latest FROM commits WHERE app_type = '#{app_type}'"
      ).first

      recent_prs = ActiveRecord::Base.connection.execute(
        "SELECT COUNT(*) as total, MAX(opened_at) as latest FROM pull_requests WHERE app_type = '#{app_type}'"
      ).first

      recent_tickets = ActiveRecord::Base.connection.execute(
        "SELECT COUNT(*) as total, MAX(created_at_jira) as latest FROM tickets WHERE app_type = '#{app_type}'"
      ).first

      # Get actual status values from tickets
      ticket_statuses = ActiveRecord::Base.connection.execute(
        "SELECT DISTINCT status FROM tickets WHERE app_type = '#{app_type}' ORDER BY status"
      ).map { |row| row["status"] }

      # Get active developers
      active_devs = ActiveRecord::Base.connection.execute(
        "SELECT COUNT(DISTINCT id) as total FROM developers WHERE app_type = '#{app_type}'"
      ).first

      context << "=== CURRENT DATA CONTEXT ==="
      context << "App: #{app_type == 'pioneer' ? 'Pioneer' : 'Legacy'}"
      context << "Active Developers: #{active_devs['total']}"
      context << "Total Commits: #{recent_commits['total']} (latest: #{recent_commits['latest']})"
      context << "Total Pull Requests: #{recent_prs['total']} (latest: #{recent_prs['latest']})"
      context << "Total Tickets: #{recent_tickets['total']} (latest: #{recent_tickets['latest']})"
      context << "Available Ticket Statuses: #{ticket_statuses.join(', ')}"
      context << "=== END CONTEXT ==="

      context.join("\n")
    rescue => e
      Rails.logger.error "Error getting database context: #{e.message}"
      ""
    end
  end

  def call_bedrock_api(user_query, app_type, schema_context = "")
    require "aws-sdk-bedrockruntime"

    # Initialize Bedrock client
    client = Aws::BedrockRuntime::Client.new(
      region: ENV["AWS_REGION"] || "us-east-1",
      credentials: Aws::Credentials.new(
        ENV["AWS_ACCESS_KEY_ID"],
        ENV["AWS_SECRET_ACCESS_KEY"]
      )
    )

    system_prompt = build_bedrock_system_prompt(app_type, schema_context)

    begin
      Rails.logger.info "Using Claude 3.5 Sonnet v2 for all queries"

      # Prepare request body for Claude
      request_body = {
        anthropic_version: "bedrock-2023-05-31",
        max_tokens: MODEL_CONFIG[:max_tokens],
        temperature: MODEL_CONFIG[:temperature],
        system: system_prompt,
        messages: [
          {
            role: "user",
            content: user_query
          }
        ]
      }

      # Make the API call
      response = client.invoke_model({
        model_id: MODEL_CONFIG[:model_id],
        body: request_body.to_json,
        content_type: "application/json"
      })

      # Parse Claude response and clean it
      response_body = JSON.parse(response.body.read)
      content = response_body.dig("content", 0, "text")

      # Clean the content to remove any potential formatting issues
      content = content.strip if content

      Rails.logger.info "=== BEDROCK AI RESPONSE ==="
      Rails.logger.info "Model: #{MODEL_CONFIG[:model_id]}"
      Rails.logger.info "Raw Response: #{content.inspect}"
      Rails.logger.info "=========================="

      content

    rescue => e
      Rails.logger.error "Bedrock API Error: #{e.message}"
      Rails.logger.error "Error Class: #{e.class}"
      Rails.logger.error "Backtrace: #{e.backtrace.first(5).join('\n')}"
      raise "Bedrock API Error: #{e.message}"
    end
  end

  def build_bedrock_system_prompt(app_type, schema_context = "")
    app_display_name = app_type == "pioneer" ? "Pioneer" : "Legacy"

    <<~PROMPT
      You are a SQL query generator for a GitHub and Jira analytics dashboard.

      IMPORTANT: Always respond with valid JSON only. No other text.
      You can handle complex queries - don't refuse unless truly impossible.

      DATABASE CONTEXT: You are querying #{app_display_name} app data only.
      #{schema_context}

      Database Tables:
      - developers (id, name, github_username, jira_username, email, app_type)
      - repositories (id, name, full_name, owner, language, app_type)#{' '}
      - commits (id, sha, message, developer_id, repository_id, committed_at, additions, deletions, app_type)
      - pull_requests (id, number, title, state, developer_id, repository_id, opened_at, closed_at, merged_at, app_type)
      - tickets (id, key, title, status, priority, developer_id, created_at_jira, updated_at_jira, app_type)

      CRITICAL FILTERING RULE:
      - ALWAYS add "app_type = '#{app_type}'" to ALL table queries
      - This ensures you only query #{app_display_name} app data

      CAPABILITIES: You can handle both simple and complex queries:
      - Simple: "top 5 developers", "count commits", "list repositories"
      - Complex: "compare team productivity trends", "analyze patterns", "correlate data across tables"
      - Use advanced SQL features (window functions, subqueries, CTEs) when needed for complex analysis

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
      8. Use subqueries, CTEs, and window functions when needed for complex logic
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

      Remember: EVERY query must filter by app_type = '#{app_type}' for ALL tables to ensure you only return #{app_display_name} app data.

      Only return {"error": "Please rephrase your query"} if the query asks for:
      - Data modification (INSERT/UPDATE/DELETE)
      - System information not in these tables
      - Truly impossible requests

      Otherwise, attempt to generate SQL for complex queries using JOINs, subqueries, HAVING, CTEs, window functions, etc.
    PROMPT
  end

  def refine_query_with_context(user_query, failed_sql, app_type, schema_context)
    begin
      Rails.logger.info "Attempting query refinement with Claude..."

      refinement_prompt = <<~PROMPT
        The following SQL query failed to return results:
        #{failed_sql}

        Original user query: "#{user_query}"

        #{schema_context}

        Please analyze what might be wrong and provide a refined SQL query that's more likely to succeed.
        Common issues:
        - Incorrect status values or field names
        - Too restrictive date ranges
        - Wrong table relationships
        - Missing data in time periods

        Respond with JSON only: {"sql": "refined query", "description": "what was fixed"}
      PROMPT

      response = call_bedrock_api(refinement_prompt, app_type)
      parse_ai_response(response)
    rescue => e
      Rails.logger.error "Query refinement error: #{e.message}"
      nil
    end
  end

  def generate_intelligent_summary(user_query, results, description, app_type)
    return nil if results.empty?

    begin
      app_display_name = app_type == "pioneer" ? "Pioneer" : "Legacy"

      # Create a rich data summary
      data_insights = analyze_results_for_insights(results)

      summary_prompt = <<~PROMPT
        You are analyzing #{app_display_name} app data results for: "#{user_query}"

        Query Description: #{description}

        Results Summary:
        - Total records: #{results.length}
        - Key insights: #{data_insights}

        Sample data:
        #{results.first(3).map { |row| row.map { |k, v| "#{k}: #{v}" }.join(", ") }.join("\n")}

        Provide an intelligent summary that:
        1. Explains what the data shows in business context
        2. Highlights the most important findings
        3. Suggests what actions or follow-up questions might be valuable
        4. Considers the #{app_display_name} team's perspective

        Respond with JSON only: {"summary": "your intelligent summary"}
      PROMPT

      response = call_bedrock_api(summary_prompt, app_type)
      parsed = parse_ai_response(response)
      parsed["summary"]
    rescue => e
      Rails.logger.error "Intelligent summary generation error: #{e.message}"
      nil
    end
  end

  def analyze_results_for_insights(results)
    return "No data" if results.empty?

    insights = []

    # Check for numeric columns and analyze distribution
    numeric_columns = results.first.select { |k, v| v.is_a?(Numeric) }

    numeric_columns.each do |column, _|
      values = results.map { |row| row[column].to_f }
      insights << "#{column}: range #{values.min}-#{values.max}, avg #{(values.sum / values.length).round(1)}"
    end

    insights.join("; ")
  end

  def execute_safe_query(sql)
    # Clean the SQL and check if it's a SELECT query (including CTEs that start with WITH)
    cleaned_sql = sql.strip.downcase
    unless cleaned_sql.start_with?("select") || cleaned_sql.start_with?("with")
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

    ActiveRecord::Base.connection.execute("SET statement_timeout = 15000")
    result = ActiveRecord::Base.connection.exec_query(sql)
    result.to_a
  end

  def format_query_results(results, ai_response, user_query)
    return { error: "No results found" } if results.empty?

    chart_type = ai_response["chart_type"] || "table"
    description = ai_response["description"] || "Query Results"

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
    columns = results.first.keys

    # For "most active" queries, prioritize the "total" column if it exists
    value_column = nil
    if columns.include?("total")
      value_column = "total"
    elsif columns.include?("total_activity")
      value_column = "total_activity"
    elsif columns.length >= 2
      # Default to second column
      value_column = columns[1]
    else
      return format_for_table(results)
    end

    # First column should be the identifier (name, etc.)
    label_column = columns[0]

    labels = results.map { |row| row[label_column].to_s }
    values = results.map { |row| row[value_column].to_i }

    Rails.logger.info "=== CHART FORMATTING ==="
    Rails.logger.info "Using label column: #{label_column}"
    Rails.logger.info "Using value column: #{value_column}"
    Rails.logger.info "Values: #{values.inspect}"
    Rails.logger.info "========================"

    {
      labels: labels,
      datasets: [ {
        label: value_column.humanize,
        data: values,
        backgroundColor: "rgba(52, 152, 219, 0.6)",
        borderColor: "rgba(52, 152, 219, 1)",
        borderWidth: 1
      } ]
    }
  end

  def format_for_pie_chart(results)
    columns = results.first.keys
    if columns.length >= 2
      labels = results.map { |row| row[columns[0]].to_s }
      data = results.map { |row| row[columns[1]].to_i }
      colors = [
        "rgba(52, 152, 219, 0.6)", "rgba(46, 204, 113, 0.6)",
        "rgba(241, 196, 15, 0.6)", "rgba(231, 76, 60, 0.6)",
        "rgba(155, 89, 182, 0.6)", "rgba(230, 126, 34, 0.6)"
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
