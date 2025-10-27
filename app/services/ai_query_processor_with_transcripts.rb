# app/services/ai_query_processor_with_transcripts.rb
class AiQueryProcessorWithTranscripts
  include BedrockAiQueryProcessor
  
  def process_query_with_transcripts(user_query, app_type = "pioneer", chat_service = nil)
    begin
      Rails.logger.info "=== AI QUERY WITH TRANSCRIPTS ==="
      Rails.logger.info "User Query: #{user_query}"
      Rails.logger.info "App Type: #{app_type}"
      
      # Extract developer name from query BEFORE any processing
      developer_name_from_query = extract_developer_name_from_query(user_query)
      Rails.logger.info "Extracted developer from query: #{developer_name_from_query}" if developer_name_from_query
      
      # Extract time period and search transcripts
      days = extract_time_period_from_ai(user_query)
      date_from = days ? days.days.ago.to_date : nil
      
      
      # Build context from conversation history and transcripts
      conversation_context = chat_service&.build_context_for_prompt(app_type) || ""
      
      # CALL 1: Generate SQL from user query
      sql_generation_response = generate_sql_from_query(
        user_query, 
        app_type, 
        conversation_context, 
        []  # No transcripts yet
      )
      
      parsed_response = parse_ai_response(sql_generation_response)

      transcript_query = parsed_response["transcript_query"] || user_query
      Rails.logger.info "Transcript search query: #{transcript_query}"

      transcript_chunks = TranscriptSearchService.search(
        transcript_query,  # Use AI-generated query
        limit: 15,
        source: 'github_jira',
        date_from: date_from
      )

      Rails.logger.info "Found #{transcript_chunks.length} transcript chunks"
      
      # Execute SQL if generated
      unless parsed_response["sql"].present?
        # If no SQL, treat as conversational query
        return handle_conversational_query(
          user_query, 
          app_type, 
          chat_service, 
          conversation_context,
          transcript_chunks
        )
      end
      
      # Execute the SQL
      sql_results = execute_safe_query(parsed_response["sql"])
      
      if sql_results.empty?
        return {
          success: false,
          error: "No data found matching your query.",
          user_query: user_query
        }
      end
      
      # CALL 2: Generate final response with actual data
      # Pass the original developer name for transcript filtering
      final_response = generate_final_response_with_data(
        user_query,
        sql_results,
        transcript_chunks,
        app_type,
        developer_name_from_query  # NEW: Pass original name
      )
      
      # Store the exchange
      chat_service&.add_exchange(
        user_query: user_query,
        sql_query: parsed_response["sql"],
        sql_results: sql_results,
        ai_response: final_response
      )
      
      {
        success: true,
        user_query: user_query,
        description: parsed_response["description"] || "Query Results",
        summary: final_response,
        raw_results: sql_results,
        sql_executed: parsed_response["sql"],
        transcript_chunks_used: transcript_chunks.length,
        processing_info: {
          model_used: MODEL_CONFIG[:model_id],
          transcripts_used: transcript_chunks.any?,
          date_filter: date_from
        }
      }
      
    rescue => e
      Rails.logger.error "AI Query with Transcripts Error: #{e.message}"
      Rails.logger.error e.backtrace.first(10).join("\n")
      { 
        success: false,
        error: "Sorry, I couldn't process your query. Please try rephrasing it.",
        user_query: user_query
      }
    end
  end
  
  private

  # Extract developer name from the original query
  def extract_developer_name_from_query(query)
    # Match capitalized names (like "Swapnil", "John Doe", etc.)
    names = query.scan(/\b[A-Z][a-z]+(?:\s+[A-Z][a-z]+)?\b/)
    
    # Filter out common words that aren't names
    common_words = %w[GitHub Jira September October November December January February March April May June July August]
    names = names.reject { |name| common_words.include?(name) }
    
    # Return first valid name found
    names.first
  end

  # Extract developer name from SQL results (fallback)
  def extract_developer_name_from_results(sql_results)
    return nil unless sql_results.is_a?(Array) && sql_results.any?
    return nil unless sql_results.first.is_a?(Hash)
    
    first_row = sql_results.first
    
    # Try different possible column names
    first_row["developer"] || first_row["name"] || first_row["developer_name"]
  end

  # CALL 1: Generate SQL from user query with context
  def generate_sql_from_query(user_query, app_type, conversation_context, _unused = nil)
    client = initialize_bedrock_client
    schema_context = get_database_context(app_type)
    
    system_prompt = build_sql_generation_prompt(
      app_type, 
      schema_context, 
      conversation_context, 
      []
    )
    
    request_body = {
      anthropic_version: "bedrock-2023-05-31",
      max_tokens: 500,
      temperature: 0.0,
      system: system_prompt,
      messages: [{ role: "user", content: "#{user_query}\n\n[Request-#{Time.now.to_f}]" }]
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
    Rails.logger.error "SQL generation error: #{e.message}"
    raise
  end

  # CALL 2: Generate final natural language response with data
  def generate_final_response_with_data(user_query, sql_results, transcript_chunks, app_type, developer_name_from_query = nil)
    client = initialize_bedrock_client
    
    # Filter transcripts using the ORIGINAL developer name from query
    filtered_transcripts = filter_transcripts_by_developer(
      transcript_chunks, 
      developer_name_from_query || extract_developer_name_from_results(sql_results)
    )
    
    system_prompt = build_response_generation_prompt(app_type, sql_results)
    
    user_prompt = build_response_user_prompt(
      user_query,
      sql_results,
      filtered_transcripts
    )
    
    request_body = {
      anthropic_version: "bedrock-2023-05-31",
      max_tokens: 2000,
      temperature: 0.3,
      system: system_prompt,
      messages: [{ role: "user", content: "#{user_prompt}\n\n[Request-#{Time.now.to_f}]" }]
    }
    
    response = client.invoke_model({
      model_id: MODEL_CONFIG[:model_id],
      body: request_body.to_json,
      content_type: "application/json"
    })
    
    response_body = JSON.parse(response.body.read)
    ai_response = response_body.dig("content", 0, "text")&.strip
    
    # Clean up response
    clean_ai_response(ai_response)
  rescue => e
    Rails.logger.error "Response generation error: #{e.message}"
    "I found the data but had trouble analyzing it. Please try rephrasing your question."
  end

  # Build system prompt for SQL generation (CALL 1)
  def build_sql_generation_prompt(app_type, schema_context, conversation_context, transcript_chunks)
    app_display_name = app_type == "pioneer" ? "Pioneer" : "Legacy"
    prompt_parts = []
    
    # Add conversation context if available
    if conversation_context.present?
      prompt_parts << conversation_context
      prompt_parts << ""
    end
    
    prompt_parts << <<~SQL_PROMPT
      You are a SQL query generator for a #{app_display_name} team analytics database.
      
      DATABASE SCHEMA:
      #{schema_context}
      
      IMPORTANT: Developer Identity Mapping
      - In JIRA tables (tickets): developers are stored by their real names (e.g., "Swapnil Bhosale")
      - In GitHub tables (commits, pull_requests): developers are stored by their GitHub usernames (e.g., "swapnil-ap")
      - These are THE SAME PERSON - you must aggregate their metrics together
      - When querying for a developer, use ILIKE to match partial names across both name fields
      
      CRITICAL RULES:
      1. Response MUST be valid JSON: {"sql":"SELECT...","description":"Brief description","transcript_query":"search terms for meeting transcripts"}
      2. FORBIDDEN: WITH clauses, CTEs, CASE WHEN, ROUND, LEAST, GREATEST, nested subqueries
      3. ONLY use: SELECT, FROM, LEFT JOIN, WHERE, GROUP BY, ORDER BY, LIMIT
      4. ALWAYS filter: app_type = '#{app_type}' on ALL tables
      5. Default time range: last 1 month (unless user specifies otherwise)
      6. Use COALESCE for nullable aggregations
      7. Use ILIKE for case-insensitive name matching
      8. If the app type is 'pioneer' then ignore the 'additions' and 'deletions' columns from the 'commits' table
      9. In ORDER BY: use the full aggregate function (COUNT(c.id)), NOT column aliases (total_commits)


      TRANSCRIPT SEARCH:
      - Include a "transcript_query" field with 2-4 relevant keywords to search meeting transcripts
      - For developer queries: use their first name only (e.g., "swapnil" not "swapnil-ap")
      - Focus on who/what to search, not the question words
      - Example: For "How was Swapnil's performance?" → "transcript_query": "swapnil performance"
      
      EXAMPLE QUERIES:
      
      For individual developer metrics (AGGREGATING ACROSS ALL THEIR ACCOUNTS):
      SELECT 
        'DeveloperName' as developer,
        COALESCE(COUNT(DISTINCT c.id), 0) as total_commits,
        COALESCE(COUNT(DISTINCT pr.id), 0) as total_prs,
        COALESCE(COUNT(DISTINCT t.id), 0) as total_tickets
      FROM developers d
      LEFT JOIN commits c ON d.id = c.developer_id 
        AND c.app_type='#{app_type}' 
        AND c.committed_at >= NOW() - INTERVAL '1 month'
      LEFT JOIN pull_requests pr ON d.id = pr.developer_id 
        AND pr.app_type='#{app_type}' 
        AND pr.opened_at >= NOW() - INTERVAL '1 month'
      LEFT JOIN tickets t ON d.id = t.developer_id 
        AND t.app_type='#{app_type}' 
        AND t.created_at_jira >= NOW() - INTERVAL '1 month'
      WHERE d.app_type = '#{app_type}' 
        AND (d.name ILIKE '%PartialName%' OR d.github_username ILIKE '%PartialName%')

      CRITICAL: Use a static string for the developer name in SELECT (e.g., 'Swapnil Bhosale').
      This aggregates all their activity across different usernames (GitHub vs JIRA).
      
      CRITICAL: When returning metrics for a specific developer, use a static string for their name in SELECT (not d.name).
      This ensures all their activity is aggregated under one name, not split by account variations (e.g., if user says "Krishna", use 'Krishna' not 'Krishna Teja').
      
      For top developers by commits:
      SELECT 
        d.name as developer,
        COUNT(c.id) as total_commits
      FROM developers d
      LEFT JOIN commits c ON d.id = c.developer_id AND c.app_type = '#{app_type}'
      WHERE d.app_type = '#{app_type}'
        AND c.committed_at >= NOW() - INTERVAL '1 month'
      GROUP BY d.name
      ORDER BY COUNT(c.id) DESC
      LIMIT 5

      For top contributors (multiple metrics):
      SELECT 
        d.name as developer,
        COUNT(DISTINCT c.id) as commits,
        COUNT(DISTINCT pr.id) as pull_requests,
        COUNT(DISTINCT t.id) as tickets
      FROM developers d
      LEFT JOIN commits c ON d.id = c.developer_id 
        AND c.app_type = '#{app_type}'
        AND c.committed_at >= NOW() - INTERVAL '1 month'
      LEFT JOIN pull_requests pr ON d.id = pr.developer_id 
        AND pr.app_type = '#{app_type}'
        AND pr.opened_at >= NOW() - INTERVAL '1 month'
      LEFT JOIN tickets t ON d.id = t.developer_id 
        AND t.app_type = '#{app_type}'
        AND t.created_at_jira >= NOW() - INTERVAL '1 month'
      WHERE d.app_type = '#{app_type}'
      GROUP BY d.name
      ORDER BY COUNT(DISTINCT c.id) + COUNT(DISTINCT pr.id) + COUNT(DISTINCT t.id) DESC
      LIMIT 5
      
      Respond with ONLY the JSON object. Nothing before {, nothing after }.
    SQL_PROMPT
    
    prompt_parts.join("\n")
  end

  # Build system prompt for response generation (CALL 2)
  def build_response_generation_prompt(app_type, sql_results)
    app_display_name = app_type == "pioneer" ? "Pioneer" : "Legacy"
    
    # Check if results show split accounts
    has_split_accounts = sql_results.length > 1 && 
                        sql_results.all? { |r| r.keys.include?("developer") }
    
    account_note = if has_split_accounts
      "\nNOTE: You may see multiple rows for the same person (different usernames for GitHub vs JIRA). Treat these as THE SAME PERSON and aggregate their metrics in your analysis."
    else
      ""
    end
    
    <<~RESPONSE_PROMPT
      You are a performance analyst for the #{app_display_name} software development team.
      
      Your job is to analyze data and provide clear, actionable insights.#{account_note}
      
      WRITING STYLE:
      - Write in short, focused paragraphs (2-4 sentences each)
      - Separate different topics with a blank line between paragraphs
      - Maximum 3 paragraphs total
      - Use bold markdown **like this** to highlight key metrics and achievements
      - Be concise and scannable - prioritize clarity over comprehensiveness
      - Focus on the most important insights only
      
      ANALYSIS GUIDELINES:
      - Combine quantitative metrics with qualitative context from meetings
      - DO NOT add the metric in response if the value is 0 (e.g., 0 tickts finished, 0 pull requests created etc)
      - If you see the same person with different usernames (e.g., "swapnil-ap" and "Swapnil Bhosale"), aggregate their metrics mentally
      - Focus on strengths, achievements, and positive contributions
      - Frame any areas for improvement constructively and supportively
      - Lead with accomplishments before mentioning growth areas
      - Use appreciative language and highlight specific positive evidence
      - Keep tone warm, encouraging, and professional
      - Default to optimistic interpretation when data is ambiguous
      
      TONE REQUIREMENTS:
      - Maintain a predominantly positive tone (100% positive, 0% constructive/negative)
      - Start with accomplishments and strong points
      - End on an uplifting or forward-looking note
      - Keep it brief - if you can't fit it in 3 short paragraphs, it's not essential
      - Use phrases like "demonstrates", "shows capability", "actively contributing" rather than negative framing

      STRUCTURE:
      Paragraph 1: Meeting insights and notable contributions (2-3 sentences, mention source as "Otter", use **bold** for source)
      Paragraph 2: Key metrics and what they show (2-3 sentences, mention source as "Github and Jira", use **bold** for source and numbers)
      Paragraph 3: Growth opportunities or forward-looking statement (1-2 sentences)
      ```
      
      IMPORTANT:
      - Use ONLY the data provided to you
      - If data is incomplete, acknowledge limitations neutrally
      - Never invent or assume information not in the data
      - Reference specific numbers and meeting insights naturally
      - When you see split accounts for the same person, treat it as one unified performance profile
    RESPONSE_PROMPT
  end

  # Build user prompt for response generation (CALL 2)
  def build_response_user_prompt(user_query, sql_results, transcript_chunks)
    prompt_parts = []
    
    prompt_parts << "ORIGINAL QUESTION:"
    prompt_parts << user_query
    prompt_parts << ""
    
    prompt_parts << "DATA FROM DATABASE:"
    prompt_parts << JSON.pretty_generate(sql_results)
    prompt_parts << ""
    
    if transcript_chunks.any?
      prompt_parts << "RELEVANT MEETING CONTEXT:"
      transcript_chunks.first(10).each_with_index do |chunk, i|
        meeting_date = chunk['meeting_date'] ? " (#{chunk['meeting_date']})" : ""
        prompt_parts << "Meeting #{i+1}#{meeting_date}:"
        prompt_parts << chunk['text'][0..600]
        prompt_parts << ""
      end
    else
      prompt_parts << "MEETING CONTEXT: No relevant meeting transcripts available."
      prompt_parts << ""
    end
    
    prompt_parts << "Generate a comprehensive response that answers the user's question using the data and meeting context provided."
    
    prompt_parts.join("\n")
  end

  # Extract developer name from SQL results (fallback)
  def extract_developer_name_from_query(query)
    # Match capitalized names (like "Swapnil", "John Doe", etc.)
    names = query.scan(/\b[A-Z][a-z]+(?:\s+[A-Z][a-z]+)?\b/)
    
    # Filter out common words that aren't names
    common_words = %w[GitHub Jira September October November December January February March April May June July August How What Where When Which Who Why]
    names = names.reject { |name| common_words.include?(name) }
    
    # Also try lowercase matching for names like "swapnil" (not capitalized in query)
    if names.empty?
      # Look for common name patterns in lowercase
      lowercase_match = query.match(/\b(john|swapnil|sarah|mike|david|alex|priya|amit|raj)\b/i)
      return lowercase_match[1].capitalize if lowercase_match
    end
    
    # Return first valid name found
    names.first
  end

  # Filter transcripts by developer name from ORIGINAL QUERY
  def filter_transcripts_by_developer(transcript_chunks, developer_name)
    return transcript_chunks if developer_name.blank?
    
    # Use the actual name for filtering (e.g., "Swapnil" not "swapnil-ap")
    name_parts = developer_name.downcase.split
    name_variations = [
      developer_name.downcase,
      name_parts.first,  # First name only
      name_parts.last    # Last name only (if exists)
    ].compact.uniq
    
    Rails.logger.info "Filtering transcripts for: #{developer_name} (variations: #{name_variations.join(', ')})"
    
    filtered = transcript_chunks.select do |chunk|
      text = chunk['text'].to_s.downcase
      name_variations.any? { |variation| text.include?(variation) }
    end
    
    Rails.logger.info "Transcript filter: #{transcript_chunks.length} → #{filtered.length} chunks for '#{developer_name}'"
    
    # If no matches, return a few transcripts anyway (better than nothing)
    filtered.any? ? filtered : transcript_chunks.first(3)
  end

  # Handle conversational queries (no SQL needed)
  def handle_conversational_query(user_query, app_type, chat_service, conversation_context, transcript_chunks)
    client = initialize_bedrock_client
    
    system_prompt = build_response_generation_prompt(app_type, [])
    
    prompt_parts = []
    
    if conversation_context.present?
      prompt_parts << conversation_context
      prompt_parts << ""
    end
    
    if transcript_chunks.any?
      prompt_parts << "RELEVANT MEETING CONTEXT:"
      transcript_chunks.first(10).each_with_index do |chunk, i|
        meeting_date = chunk['meeting_date'] ? " (#{chunk['meeting_date']})" : ""
        prompt_parts << "Meeting #{i+1}#{meeting_date}:"
        prompt_parts << chunk['text'][0..400]
        prompt_parts << ""
      end
    end
    
    prompt_parts << "USER QUESTION:"
    prompt_parts << user_query
    prompt_parts << ""
    prompt_parts << "Provide a helpful, concise response based on software development best practices and any available context."
    
    request_body = {
      anthropic_version: "bedrock-2023-05-31",
      max_tokens: 1000,
      temperature: 0.3,
      system: system_prompt,
      messages: [{ role: "user", content: "#{prompt_parts.join("\n")}\n\n[Request-#{Time.now.to_f}]" }]
    }
    
    response = client.invoke_model({
      model_id: MODEL_CONFIG[:model_id],
      body: request_body.to_json,
      content_type: "application/json"
    })
    
    response_body = JSON.parse(response.body.read)
    ai_response = response_body.dig("content", 0, "text")&.strip
    
    chat_service&.add_conversational_exchange(user_query, clean_ai_response(ai_response))
    
    {
      success: true,
      user_query: user_query,
      description: "AI Assistant Response",
      summary: clean_ai_response(ai_response),
      transcript_chunks_used: transcript_chunks.length,
      processing_info: {
        model_used: MODEL_CONFIG[:model_id],
        query_type: "conversational",
        transcripts_used: transcript_chunks.any?
      }
    }
  rescue => e
    Rails.logger.error "Conversational query error: #{e.message}"
    {
      success: false,
      error: "Sorry, I couldn't process your question. Please try rephrasing it.",
      user_query: user_query
    }
  end

  # Clean up AI response text
  def clean_ai_response(response)
    return "" unless response.present?
    
    # Remove quotes if wrapped
    cleaned = response.gsub(/^["']|["']$/, '').strip
    
    # Remove any "Note:" sections
    cleaned = cleaned.split(/\n\n?Note:/i).first&.strip || cleaned
    
    # Convert numbered lists to paragraphs if present
    if cleaned.match?(/^\d+\.\s/)
      Rails.logger.warn "AI returned numbered list - converting to paragraph"
      cleaned = cleaned.gsub(/^\d+\.\s+/, '').gsub(/\n+/, ' ')
    end
    
    # Convert bullet lists to paragraphs if present
    if cleaned.match?(/^[•\-\*]\s/)
      Rails.logger.warn "AI returned bullet list - converting to paragraph"
      cleaned = cleaned.gsub(/^[•\-\*]\s+/, '').gsub(/\n+/, ' ')
    end
    
    cleaned.strip
  end

  # Extract time period from query using AI
  def extract_time_period_from_ai(query)
    client = initialize_bedrock_client
    
    request_body = {
      anthropic_version: "bedrock-2023-05-31",
      max_tokens: 10,
      temperature: 0.0,
      messages: [{ 
        role: "user", 
        content: "Extract time period as days from: '#{query}'. Examples: 'last week'→7, 'last month'→30, 'last 45 days'→45, 'all time'→null. Respond with ONLY the number or null." 
      }]
    }
    
    response = client.invoke_model({
      model_id: MODEL_CONFIG[:model_id],
      body: request_body.to_json,
      content_type: "application/json"
    })
    
    response_body = JSON.parse(response.body.read)
    ai_response = response_body.dig("content", 0, "text")&.strip
    
    return nil if ai_response == "null"
    ai_response.to_i > 0 ? ai_response.to_i : 30
  rescue => e
    Rails.logger.error "Time extraction error: #{e.message}"
    30  # Default to 30 days
  end
end
