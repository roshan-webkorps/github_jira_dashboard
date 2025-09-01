module BedrockAiQueryProcessor
  extend ActiveSupport::Concern

  MODEL_CONFIG = {
    model_id: "us.anthropic.claude-3-5-sonnet-20241022-v2:0",
    max_tokens: 500,
    temperature: 0.1
  }.freeze

  def process_bedrock_ai_query(user_query, app_type = "pioneer", chat_service = nil)
    begin
      Rails.logger.info "=== BEDROCK QUERY PROCESSING ==="
      Rails.logger.info "User Query: #{user_query}"
      Rails.logger.info "App Type: #{app_type}"
      Rails.logger.info "Has Context: #{chat_service&.has_context?}"

      unless is_data_query?(user_query)
        return handle_conversational_query(user_query, app_type, chat_service)
      end

      # Get database context
      schema_context = get_database_context(app_type)

      # Get conversation context if available
      conversation_context = chat_service&.build_context_for_prompt(app_type) || ""

      # Generate query using Claude
      ai_response = call_bedrock_api(user_query, app_type, schema_context, conversation_context)
      parsed_response = parse_ai_response(ai_response)

      # Execute and validate query
      if parsed_response["sql"].present?
        results = execute_safe_query(parsed_response["sql"])

        # Format results using Ai::ChartFormatter
        formatted_results = Ai::ChartFormatter.format_results(results, parsed_response, user_query)

        # Generate business-friendly summary using Ai::SummaryGenerator
        if formatted_results[:success] && results.any? && (results.length > 3 || parsed_response["chart_type"] != "table")
          bedrock_client = initialize_bedrock_client
          summary_generator = Ai::SummaryGenerator.new(bedrock_client)
          summary = summary_generator.generate_business_summary(
            user_query, results, parsed_response["description"], app_type
          )
          formatted_results[:summary] = summary if summary
        end

        # Add exchange to chat context
        chat_service&.add_exchange(user_query, parsed_response, formatted_results)

        # Add processing metadata
        formatted_results[:processing_info] = {
          model_used: MODEL_CONFIG[:model_id],
          context_used: conversation_context.present?
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

  def is_data_query?(user_query)
    data_keywords = [
      "show", "list", "find", "get", "top", "most", "least", "how many", "count", "features",
      "commits", "pull requests", "tickets", "developers", "repositories", "repos", "month",
      "activity", "stats", "metrics", "performance", "open", "closed", "completed", "year"
    ]

    query_lower = user_query.downcase
    data_keywords.any? { |keyword| query_lower.include?(keyword) }
  end

  private

  def initialize_bedrock_client
    require "aws-sdk-bedrockruntime"

    Aws::BedrockRuntime::Client.new(
      region: ENV["AWS_REGION"] || "us-east-1",
      credentials: Aws::Credentials.new(
        ENV["AWS_ACCESS_KEY_ID"],
        ENV["AWS_SECRET_ACCESS_KEY"]
      )
    )
  end

  def call_bedrock_api(user_query, app_type, schema_context = "", conversation_context = "")
    client = initialize_bedrock_client
    system_prompt = build_system_prompt(app_type, schema_context, conversation_context)

    request_body = {
      anthropic_version: "bedrock-2023-05-31",
      max_tokens: MODEL_CONFIG[:max_tokens],
      temperature: MODEL_CONFIG[:temperature],
      system: system_prompt,
      messages: [ { role: "user", content: user_query } ]
    }

    response = client.invoke_model({
      model_id: MODEL_CONFIG[:model_id],
      body: request_body.to_json,
      content_type: "application/json"
    })

    response_body = JSON.parse(response.body.read)
    content = response_body.dig("content", 0, "text")
    content&.strip
  rescue => e
    Rails.logger.error "Bedrock API call error: #{e.message}"
    Rails.logger.error "Backtrace: #{e.backtrace.first(3)}"
    raise
  end

  def build_system_prompt(app_type, schema_context, conversation_context, user_query = "")
    app_display_name = app_type == "pioneer" ? "Pioneer" : "Legacy"
    prompt_parts = []

    # Add conversation context at the top if available
    if conversation_context.present?
      prompt_parts << conversation_context
      prompt_parts << ""
    end

    prompt_parts << <<~BASE_PROMPT
      You are a SQL query generator for a GitHub and Jira analytics dashboard.

      CRITICAL JSON FORMAT REQUIREMENTS:
      - ALWAYS respond with EXACTLY this JSON structure - no variations
      - Do NOT use WITH clauses, CTEs, or subqueries
      - Keep SQL simple with basic SELECT, JOIN, WHERE, GROUP BY, ORDER BY only
      - Use single quotes for all string values in SQL (not double quotes)
      - Do NOT use column aliases with double quotes like "Developer Name"
      - Use simple column aliases: name AS developer_name (no quotes)
      - For ORDER BY: use numbers (ORDER BY 1, 2) or repeat the expression, NOT column aliases

      REQUIRED RESPONSE FORMAT (copy this structure exactly):
      {"sql": "SELECT simple query here", "description": "Brief description", "chart_type": "bar"}

      DATABASE CONTEXT: You are querying #{app_display_name} app data only.
      #{schema_context}

      Database Tables:
      - developers (id, name, github_username, jira_username, email, app_type)
      - repositories (id, name, full_name, owner, language, app_type)
      - commits (id, sha, message, developer_id, repository_id, committed_at, additions, deletions, app_type)
      - pull_requests (id, number, title, state, developer_id, repository_id, opened_at, closed_at, merged_at, app_type)
      - tickets (id, key, title, status, priority, developer_id, created_at_jira, updated_at_jira, app_type)

      CRITICAL FILTERING RULE:
      - ALWAYS add "app_type = '#{app_type}'" to ALL table queries

      COMPARISON QUERY RULES:
      - For time comparisons like "January vs March" or "Q1 vs Q2", create AGGREGATE totals, not per-developer breakdowns
      - NEVER reference column aliases in ORDER BY - use column numbers instead
      - For "compare X vs Y" queries, return just TWO rows: one for each time period
      - Use UNION to combine separate time period queries into aggregate results
      - Format: SELECT 'Period Name' as period, COUNT/SUM as total

      DEFAULT TIME FRAME RULE:
      - Unless a specific time frame is mentioned in the query, ALWAYS filter data to the last 1 month
      - For commits: use "committed_at >= NOW() - INTERVAL '1 month'"
      - For pull_requests: use "opened_at >= NOW() - INTERVAL '1 month'" (or closed_at/merged_at if query is about closed/merged PRs)
      - For tickets: use "created_at_jira >= NOW() - INTERVAL '1 month'" (or updated_at_jira if query is about updates)
      - If user specifies a different time frame (e.g., "last 6 months", "this year", "last week"), use that instead
      - If query asks for "all time" or "ever" or similar, don't apply time filtering
      - For year comparisons, use current year 2025

      SQL SIMPLICITY RULES:
      1. ONLY use basic SELECT queries - no CTEs, no WITH clauses, no subqueries
      2. Always JOIN with developers table to show names, not IDs
      3. ALWAYS filter by app_type = '#{app_type}' for ALL tables
      4. Use simple column names in SELECT - no quoted aliases
      5. Use ORDER BY with numbers: ORDER BY 1 DESC, not ORDER BY alias_name DESC
      6. For UNION queries, ensure both SELECT statements have identical column structure
      7. Use appropriate LIMIT: LIMIT 5 for top/most queries, LIMIT 10 for lists, no LIMIT for counts or comparisons
      8. For ticket statuses, use proper mapping:
        - "closed/completed/done" = status IN ('Done', 'Deployed', 'Ready For Release')
        - "open/pending/todo" = status IN ('To Do', 'BLOCKED', 'Need More Info')
        - "in progress/active" = status IN ('In Progress', 'Code Review', 'Testing')

      EXAMPLE RESPONSES:

      Simple query:
      {"sql": "SELECT d.name, COUNT(pr.id) as pr_count FROM developers d JOIN pull_requests pr ON d.id = pr.developer_id WHERE pr.app_type = 'pioneer' AND d.app_type = 'pioneer' AND pr.merged_at >= NOW() - INTERVAL '1 month' AND pr.merged_at IS NOT NULL GROUP BY d.name ORDER BY 2 DESC LIMIT 5", "description": "Top 5 developers with most merged pull requests this month", "chart_type": "bar"}

      Comparison query (AGGREGATE format):
      {"sql": "SELECT 'January' as period, COUNT(c.id) as total FROM commits c JOIN developers d ON c.developer_id = d.id WHERE c.app_type = 'pioneer' AND d.app_type = 'pioneer' AND c.committed_at >= '2025-01-01' AND c.committed_at < '2025-02-01' UNION SELECT 'March' as period, COUNT(c.id) as total FROM commits c JOIN developers d ON c.developer_id = d.id WHERE c.app_type = 'pioneer' AND d.app_type = 'pioneer' AND c.committed_at >= '2025-03-01' AND c.committed_at < '2025-04-01'", "description": "Total commit comparison between January and March 2025", "chart_type": "bar"}

      Chart types: "bar" for rankings/counts, "pie" for distributions, "table" for lists.

      Remember: Keep it simple, no complex SQL, exact JSON format only, use ORDER BY with numbers not aliases.
    BASE_PROMPT

    prompt_parts.join("\n")
  end

  def parse_ai_response(ai_response)
  return {} if ai_response.nil? || ai_response.strip.empty?

    cleaned_response = clean_response(ai_response)
    result = JSON.parse(cleaned_response)
    result
  rescue JSON::ParserError => e
    Rails.logger.error "JSON parsing failed: #{e.message}"
    Rails.logger.info "Attempting regex extraction..."

    extracted = extract_with_regex(cleaned_response)
    Rails.logger.info "Regex extracted: #{extracted.inspect}"

    extracted || raise(JSON::ParserError, "Could not parse AI response")
  end

  def clean_response(response)
    cleaned = response.strip
    cleaned = cleaned[1...-1] if cleaned.start_with?('"') && cleaned.end_with?('"')
    cleaned.gsub('\\n', "\n").gsub('\\r', "\r").gsub('\\t', "\t").gsub('\\"', '"').gsub("\\\\", "\\")
  end

  def extract_with_regex(response)
    result = {}

    # Extract key fields with regex
    {
      "sql" => /"sql":\s*"((?:[^"\\]|\\.)*)"/m,
      "description" => /"description":\s*"((?:[^"\\]|\\.)*)"/m,
      "chart_type" => /"chart_type":\s*"((?:[^"\\]|\\.)*)"/m,
      "summary" => /"summary":\s*"((?:[^"\\]|\\.)*)"/m
    }.each do |key, pattern|
      match = response.match(pattern)
      result[key] = match[1].gsub('\\"', '"').gsub("\\\\", "\\") if match
    end

    result.any? ? result : nil
  end

  def get_database_context(app_type)
    <<~SCHEMA
      === DATABASE SCHEMA DETAILS ===

      developers:
        - id (primary key)
        - name (developer display name)
        - github_username, jira_username
        - email, app_type

      commits:
        - id, sha, message
        - developer_id (foreign key to developers.id)
        - repository_id (foreign key to repositories.id)
        - committed_at (timestamp)
        - additions, deletions (code changes)
        - app_type

      pull_requests:
        - id, number, title, state
        - developer_id (foreign key to developers.id)
        - repository_id (foreign key to repositories.id)
        - opened_at, closed_at, merged_at (timestamps)
        - app_type

      tickets:
        - id, key (Jira ticket key), title, status, priority
        - developer_id (foreign key to developers.id)
        - created_at_jira, updated_at_jira (timestamps)
        - app_type

      repositories:
        - id, name, full_name, owner, language
        - app_type

      === RELATIONSHIPS ===
      - All tables have app_type column for filtering
      - developers.id connects to commits, pull_requests, tickets
      - repositories.id connects to commits, pull_requests
      - Use JOINs to get developer names instead of IDs

      Current app_type: #{app_type}
    SCHEMA
  end

  def refine_query_with_context(user_query, failed_sql, app_type, schema_context)
    Rails.logger.info "Attempting query refinement..."

    refinement_prompt = <<~PROMPT
      The following SQL query returned no results:
      #{failed_sql}

      Original query: "#{user_query}"
      #{schema_context}

      Provide a refined SQL query that's more likely to succeed.
      Common fixes: broader date ranges, correct status values, proper joins.

      Respond with JSON: {"sql": "refined query", "description": "what was fixed"}
    PROMPT

    response = call_bedrock_api(refinement_prompt, app_type)
    parse_ai_response(response)
  rescue => e
    Rails.logger.error "Query refinement error: #{e.message}"
    nil
  end

  def execute_safe_query(sql)
    cleaned_sql = sql.strip.downcase
    unless cleaned_sql.start_with?("select") || cleaned_sql.start_with?("with")
      raise "Only SELECT queries are allowed"
    end

    dangerous_patterns = [
      /\b(drop|delete|insert|alter|create|truncate)\s+/i,
      /;\s*(drop|delete|insert|alter|create|truncate)/i,
      /\bupdate\s+\w+\s+set\b/i
    ]

    if dangerous_patterns.any? { |pattern| sql.match?(pattern) }
      raise "Query contains prohibited SQL commands"
    end

    ActiveRecord::Base.connection.execute("SET statement_timeout = 15000")
    result = ActiveRecord::Base.connection.exec_query(sql)
    result.to_a
  end

  def handle_conversational_query(user_query, app_type, chat_service)
    # Get conversation context if available
    conversation_context = chat_service&.build_context_for_prompt(app_type) || ""

    # Create a conversational prompt instead of SQL generation
    conversational_prompt = build_conversational_prompt(user_query, app_type, conversation_context)

    ai_response = call_bedrock_api_conversational(conversational_prompt)

    # Add to chat context as non-data exchange
    chat_service&.add_conversational_exchange(user_query, ai_response)

    {
      success: true,
      user_query: user_query,
      description: "AI Assistant Response",
      chart_type: "text",
      response: ai_response,
      processing_info: {
        model_used: MODEL_CONFIG[:model_id],
        context_used: conversation_context.present?,
        query_type: "conversational"
      }
    }
  rescue => e
    Rails.logger.error "Conversational AI Error: #{e.message}"
    { error: "Sorry, I couldn't process your question. Please try rephrasing it." }
  end

  def build_conversational_prompt(user_query, app_type, conversation_context)
    app_display_name = app_type == "pioneer" ? "Pioneer" : "Legacy"

    prompt_parts = []

    if conversation_context.present?
      prompt_parts << conversation_context
      prompt_parts << ""
    end

    prompt_parts << <<~PROMPT
      You are an AI assistant for a GitHub and Jira analytics dashboard for the #{app_display_name} team.

      The user is asking for advice or having a conversation about their development team management.
      Provide helpful, actionable advice based on software development best practices.

      Keep responses concise but informative (2-4 sentences).
      Focus on practical steps and recommendations.

      User question: #{user_query}
    PROMPT

    prompt_parts.join("\n")
  end

  def call_bedrock_api_conversational(prompt)
    client = initialize_bedrock_client

    request_body = {
      anthropic_version: "bedrock-2023-05-31",
      max_tokens: 300,
      temperature: 0.3,
      system: "You are a helpful assistant for development team management. Provide concise, actionable advice.",
      messages: [ { role: "user", content: prompt } ]
    }

    response = client.invoke_model({
      model_id: MODEL_CONFIG[:model_id],
      body: request_body.to_json,
      content_type: "application/json"
    })

    response_body = JSON.parse(response.body.read)
    response_body.dig("content", 0, "text")&.strip
  end

  def call_bedrock_api(user_query, app_type, schema_context = "", conversation_context = "")
    client = initialize_bedrock_client
    system_prompt = build_system_prompt(app_type, schema_context, conversation_context, user_query)

    request_body = {
      anthropic_version: "bedrock-2023-05-31",
      max_tokens: MODEL_CONFIG[:max_tokens],
      temperature: MODEL_CONFIG[:temperature],
      system: system_prompt,
      messages: [ { role: "user", content: user_query } ]
    }

    response = client.invoke_model({
      model_id: MODEL_CONFIG[:model_id],
      body: request_body.to_json,
      content_type: "application/json"
    })

    response_body = JSON.parse(response.body.read)
    content = response_body.dig("content", 0, "text")
    content&.strip
  rescue => e
    Rails.logger.error "Bedrock API call error: #{e.message}"
    Rails.logger.error "Backtrace: #{e.backtrace.first(3)}"
    raise
  end
end
