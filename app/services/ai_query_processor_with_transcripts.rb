# app/services/ai_query_processor_with_transcripts.rb
class AiQueryProcessorWithTranscripts
  include BedrockAiQueryProcessor
  
  def process_query_with_transcripts(user_query, app_type = "pioneer", chat_service = nil)
    begin
      Rails.logger.info "=== AI QUERY WITH TRANSCRIPTS ==="
      Rails.logger.info "User Query: #{user_query}"
      Rails.logger.info "App Type: #{app_type}"
      
      # Check if this is a follow-up question that can be answered from stored analysis
      if is_followup_question?(user_query)
        followup_result = handle_followup_question(user_query, chat_service)
        return followup_result if followup_result
      end
      
      # Extract time period and search transcripts
      days = extract_time_period_from_ai(user_query)
      date_from = days ? days.days.ago.to_date : nil
      
      transcript_chunks = TranscriptSearchService.search(
        user_query, 
        limit: 30, 
        source: 'github_jira',
        date_from: date_from
      )
      
      Rails.logger.info "Found #{transcript_chunks.length} transcript chunks from meetings since #{date_from}"
      
      # Check if this is a data query
      unless is_data_query?(user_query)
        return handle_conversational_with_transcripts(user_query, app_type, chat_service, transcript_chunks)
      end
      
      # Get database context and generate SQL
      schema_context = get_database_context(app_type)
      conversation_context = chat_service&.build_context_for_prompt(app_type) || ""
      
      ai_response = call_bedrock_with_transcripts(
        user_query, app_type, schema_context, conversation_context, transcript_chunks
      )
      
      parsed_response = parse_ai_response(ai_response)
      
      # Execute SQL if present
      if parsed_response["sql"].present?
        results = execute_safe_query(parsed_response["sql"])
        formatted_results = Ai::ChartFormatter.format_results(results, parsed_response, user_query)
        
        # Generate comprehensive analysis with both SQL results and transcripts
        if formatted_results[:success] && results.any?
          developer_name = extract_developer_name_from_results(results)
          
          if developer_name.present?
            # Generate FULL analysis once and store it
            full_analysis = generate_full_developer_analysis(
              developer_name,
              results,
              transcript_chunks,
              app_type
            )
            
            # Store the comprehensive analysis
            chat_service&.store_developer_analysis(developer_name, full_analysis)
            
            # Return just the performance summary for now
            formatted_results[:summary] = full_analysis[:performance_summary]
            formatted_results[:has_detailed_analysis] = true
          end
        end
        
        formatted_results[:transcript_chunks_used] = transcript_chunks.length
        formatted_results[:processing_info] = {
          model_used: MODEL_CONFIG[:model_id],
          context_used: conversation_context.present?,
          transcripts_used: transcript_chunks.any?
        }
        
        chat_service&.add_exchange(user_query, parsed_response, formatted_results)
        formatted_results
      else
        { error: "Could not generate a valid query from your request." }
      end
      
    rescue => e
      Rails.logger.error "AI Query with Transcripts Error: #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")
      { error: "Sorry, I couldn't process your query. Please try rephrasing it." }
    end
  end
  
  private

  # Check if this is a follow-up question about improvements/strengths
  def is_followup_question?(query)
    has_pronoun = query.match?(/\b(he|she|they|his|her|their)\b/i)
    is_improvement_question = query.match?(/improve|better|enhance|develop|grow|work on|focus on/i)
    is_strength_question = query.match?(/strength|strong|good at|excel|best|strong point/i)
    
    has_pronoun && (is_improvement_question || is_strength_question)
  end

  # Handle follow-up questions using stored analysis
  def handle_followup_question(user_query, chat_service)
    return nil unless chat_service
    
    developer_name = extract_developer_from_context_or_query(user_query, chat_service)
    
    unless developer_name.present?
      Rails.logger.warn "Follow-up question but no developer in context"
      return nil  # Fall through to normal processing
    end
    
    # Check if we have stored analysis
    unless chat_service.has_analysis_for?(developer_name)
      Rails.logger.warn "No stored analysis for #{developer_name}"
      return nil  # Fall through to normal processing
    end
    
    # Determine what type of analysis to retrieve
    analysis_type = if user_query.match?(/improve|better|enhance|develop|grow|work on|focus on/i)
      :improvements
    elsif user_query.match?(/strength|strong|good at|excel|best|strong point/i)
      :strengths
    else
      :summary
    end
    
    # Get pre-computed analysis
    response = chat_service.get_developer_analysis(developer_name, analysis_type)
    
    Rails.logger.info "Retrieved #{analysis_type} analysis for #{developer_name} from storage"
    
    chat_service.add_conversational_exchange(user_query, response)
    
    {
      success: true,
      user_query: user_query,
      description: "Developer Analysis (Retrieved from Storage)",
      chart_type: "text",
      response: response,
      transcript_chunks_used: 0,
      processing_info: {
        model_used: "stored_analysis",
        query_type: "followup",
        source: "pre_computed",
        developer: developer_name
      }
    }
  end

  # Extract developer name from SQL results
  def extract_developer_name_from_results(results)
    return nil unless results.is_a?(Array) && results.first.is_a?(Hash)
    
    first_row = results.first
    first_row["developer"] || first_row["name"] || first_row["developer_name"]
  end

  # Generate comprehensive analysis ONE TIME with all the context
  def generate_full_developer_analysis(developer_name, sql_results, transcript_chunks, app_type)
    # Filter transcripts to only those mentioning this developer
    filtered_transcripts = filter_transcripts_by_developer(transcript_chunks, developer_name)
    
    transcripts_text = if filtered_transcripts.any?
      filtered_transcripts.first(5).map.with_index do |chunk, i|
        meeting_date = chunk['meeting_date'] ? " on #{chunk['meeting_date']}" : ""
        "Transcript #{i+1}#{meeting_date}:\n#{chunk['text'][0..600]}"
      end.join("\n\n")
    else
      "No meeting transcripts available for #{developer_name}"
    end
    
    prompt = <<~PROMPT
      You are analyzing #{developer_name}'s individual performance as a software developer.
      
      Performance Metrics:
      #{sql_results.to_json}
      
      Meeting Context:
      #{transcripts_text}
      
      Generate a comprehensive analysis with THREE distinct sections. Output ONLY valid JSON in this exact format:
      {
        "performance_summary": "2-3 sentences summarizing #{developer_name}'s recent performance and activity level",
        "strengths": "4-5 sentences describing #{developer_name}'s key strengths, what they excel at, and positive behaviors",
        "improvements": "4-5 sentences detailing specific areas where #{developer_name} can improve with concrete, actionable steps they can take"
      }
      
      CRITICAL RULES:
      1. Write in natural paragraph form (NO bullet points, NO numbered lists)
      2. Focus ONLY on #{developer_name} as an individual
      3. Be specific and actionable
      4. Use #{developer_name}'s name naturally in the text
      5. Return ONLY the JSON object, nothing else
    PROMPT
    
    response = call_bedrock_for_analysis(prompt)
    
    # Parse and validate the response
    begin
      # Clean up the response (remove markdown code blocks if present)
      cleaned_response = response.gsub(/```json\n?|\n?```/, '').strip
      
      parsed = JSON.parse(cleaned_response)
      
      {
        performance_summary: parsed["performance_summary"] || "Analysis for #{developer_name}",
        strengths: parsed["strengths"] || "#{developer_name} demonstrates consistent contributions.",
        improvements: parsed["improvements"] || "#{developer_name} could focus on continuous skill development.",
        metrics: sql_results.first,
        generated_at: Time.current
      }
    rescue JSON::ParserError => e
      Rails.logger.error "Failed to parse analysis JSON: #{e.message}"
      Rails.logger.error "Response was: #{response}"
      
      # Fallback: Generate generic but correct analysis
      {
        performance_summary: build_generic_summary(developer_name, sql_results.first),
        strengths: build_generic_strengths(developer_name),
        improvements: build_generic_improvements(developer_name),
        metrics: sql_results.first,
        generated_at: Time.current
      }
    end
  end

  # Fallback methods for when AI fails to return valid JSON
  def build_generic_summary(developer_name, metrics)
    commits = metrics["total_commits"] || 0
    prs = metrics["total_prs"] || 0
    tickets = metrics["total_tickets"] || 0
    
    "Based on recent metrics, #{developer_name} has contributed #{commits} commits, #{prs} pull requests, and completed #{tickets} tickets. This shows #{commits > 10 ? 'strong' : 'moderate'} development activity and engagement with the project."
  end

  def build_generic_strengths(developer_name)
    "#{developer_name} demonstrates consistent contributions to the codebase and shows reliability in completing assigned tasks. They participate actively in the development process and contribute to team deliverables. #{developer_name}'s work shows attention to meeting project requirements and maintaining development momentum."
  end

  def build_generic_improvements(developer_name)
    "#{developer_name} could enhance their impact by increasing participation in code reviews, providing thoughtful feedback to teammates, and sharing knowledge more actively. Dedicating time to learn new technologies or deepen expertise in the current tech stack would boost productivity and code quality. Additionally, improving documentation practices and writing clearer commit messages would make their contributions more valuable to the team and easier for others to understand."
  end

  # Call Bedrock specifically for generating structured analysis
  def call_bedrock_for_analysis(prompt)
    client = initialize_bedrock_client
    
    request_body = {
      anthropic_version: "bedrock-2023-05-31",
      max_tokens: 2000,
      temperature: 0.2,
      system: "You are a performance analyst. Generate valid JSON only. Write in natural paragraph form without bullet points or numbered lists.",
      messages: [{ role: "user", content: prompt }]
    }
    
    response = client.invoke_model({
      model_id: MODEL_CONFIG[:model_id],
      body: request_body.to_json,
      content_type: "application/json"
    })
    
    response_body = JSON.parse(response.body.read)
    response_body.dig("content", 0, "text")&.strip
  end

  def extract_developer_from_context_or_query(user_query, chat_service)
    # Try to extract from current query (capitalized names)
    developer_name = user_query.scan(/\b[A-Z][a-z]+\b/).first
    
    # If not found and there's a pronoun, check chat context
    if developer_name.nil? && chat_service
      has_pronoun = user_query.match?(/\b(he|she|they|him|her|his|their)\b/i)
      
      if has_pronoun
        developers_in_context = chat_service.data_context[:developers]
        developer_name = developers_in_context&.first if developers_in_context&.any?
        Rails.logger.info "Extracted developer from context: #{developer_name}" if developer_name.present?
      end
    end
    
    developer_name
  end

  def filter_transcripts_by_developer(transcript_chunks, developer_name)
    return transcript_chunks if developer_name.blank?
    
    name_parts = developer_name.downcase.split
    name_variations = [
      developer_name.downcase,
      name_parts.first,
      name_parts.last
    ].compact.uniq
    
    filtered = transcript_chunks.select do |chunk|
      text = chunk['text'].to_s.downcase
      name_variations.any? { |variation| text.include?(variation) }
    end
    
    Rails.logger.info "Transcript filter: #{transcript_chunks.length} → #{filtered.length} chunks for '#{developer_name}'"
    filtered
  end

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
    30
  end
  
  def call_bedrock_with_transcripts(user_query, app_type, schema_context, conversation_context, transcript_chunks)
    client = initialize_bedrock_client
    system_prompt = build_system_prompt_with_transcripts(
      app_type, schema_context, conversation_context, transcript_chunks
    )
    
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
    raise
  end
  
  def build_system_prompt_with_transcripts(app_type, schema_context, conversation_context, transcript_chunks)
    app_display_name = app_type == "pioneer" ? "Pioneer" : "Legacy"
    prompt_parts = []
    
    prompt_parts << conversation_context << "" if conversation_context.present?
    
    if transcript_chunks.any?
      prompt_parts << "=== RELEVANT MEETING TRANSCRIPTS ==="
      transcript_chunks.each_with_index do |chunk, i|
        prompt_parts << "Transcript #{i+1}:"
        prompt_parts << "Meeting Date: #{chunk['meeting_date']}" if chunk['meeting_date'].present?
        prompt_parts << "Content: #{chunk['text'][0..800]}"
        prompt_parts << ""
      end
      prompt_parts << ""
    end
    
    prompt_parts << <<~BASE_PROMPT
      SQL QUERY GENERATOR FOR #{app_display_name.upcase}

      CRITICAL FORMAT: Response MUST be valid JSON: {"sql":"SELECT...","description":"...","chart_type":"bar"}
      
      SQL CONSTRAINTS:
      - FORBIDDEN: WITH clauses, CTEs, CASE WHEN, ROUND, LEAST, GREATEST, nested subqueries
      - ONLY use: SELECT, FROM, LEFT JOIN, WHERE, GROUP BY, ORDER BY, LIMIT
      - Filter: app_type = '#{app_type}' on ALL tables
      - Time: last 1 month unless specified
      
      FOR INDIVIDUAL DEVELOPER:
      SELECT 
        'DeveloperName' as developer,
        COALESCE(SUM(c.cnt), 0) as total_commits,
        COALESCE(SUM(p.cnt), 0) as total_prs,
        COALESCE(SUM(t.cnt), 0) as total_tickets,
        COALESCE(SUM(c.changes), 0) as total_code_changes
      FROM developers d
      LEFT JOIN (SELECT developer_id, COUNT(*) as cnt, SUM(additions+deletions) as changes FROM commits WHERE app_type='#{app_type}' AND committed_at >= NOW() - INTERVAL '1 month' GROUP BY developer_id) c ON d.id = c.developer_id
      LEFT JOIN (SELECT developer_id, COUNT(*) as cnt FROM pull_requests WHERE app_type='#{app_type}' AND opened_at >= NOW() - INTERVAL '1 month' GROUP BY developer_id) p ON d.id = p.developer_id
      LEFT JOIN (SELECT developer_id, COUNT(*) as cnt FROM tickets WHERE app_type='#{app_type}' AND created_at_jira >= NOW() - INTERVAL '1 month' GROUP BY developer_id) t ON d.id = t.developer_id
      WHERE d.app_type = '#{app_type}' AND (d.name ILIKE '%Name%' OR d.github_username ILIKE '%name%')
      
      Chart types: bar, pie, table
      Respond with ONLY the JSON. Nothing before {, nothing after }
    BASE_PROMPT
    
    prompt_parts.join("\n")
  end
  
  def handle_conversational_with_transcripts(user_query, app_type, chat_service, transcript_chunks)
    conversation_context = chat_service&.build_context_for_prompt(app_type) || ""
    
    prompt_parts = []
    prompt_parts << conversation_context << "" if conversation_context.present?
    
    if transcript_chunks.any?
      prompt_parts << "=== RELEVANT MEETING TRANSCRIPTS ==="
      transcript_chunks.first(5).each do |chunk|
        meeting_date = chunk['meeting_date'] ? " (#{chunk['meeting_date']})" : ""
        prompt_parts << "- #{meeting_date}: #{chunk['text'][0..400]}"
      end
      prompt_parts << ""
    end
    
    prompt_parts << <<~PROMPT
      You are an AI assistant for a GitHub/Jira analytics dashboard (#{app_type} team).
      Provide helpful advice based on software development best practices.
      Keep responses concise and actionable (3-4 sentences).
      
      User question: #{user_query}
    PROMPT
    
    ai_response = call_bedrock_for_synthesis(prompt_parts.join("\n"))
    chat_service&.add_conversational_exchange(user_query, ai_response)
    
    {
      success: true,
      user_query: user_query,
      description: "AI Assistant Response",
      chart_type: "text",
      response: ai_response,
      transcript_chunks_used: transcript_chunks.length,
      processing_info: {
        model_used: MODEL_CONFIG[:model_id],
        context_used: conversation_context.present?,
        transcripts_used: transcript_chunks.any?,
        query_type: "conversational"
      }
    }
  rescue => e
    Rails.logger.error "Conversational AI Error: #{e.message}"
    { error: "Sorry, I couldn't process your question. Please try rephrasing it." }
  end

  def call_bedrock_for_synthesis(prompt)
    client = initialize_bedrock_client
    
    request_body = {
      anthropic_version: "bedrock-2023-05-31",
      max_tokens: 1000,
      temperature: 0.3,
      system: "You are a performance analyst. Write in natural paragraph form. NEVER use lists or bullets.",
      messages: [ { role: "user", content: prompt } ]
    }
    
    response = client.invoke_model({
      model_id: MODEL_CONFIG[:model_id],
      body: request_body.to_json,
      content_type: "application/json"
    })
    
    response_body = JSON.parse(response.body.read)
    summary = response_body.dig("content", 0, "text")&.strip
    
    if summary
      summary = summary.gsub(/^["']|["']$/, '')
      summary = summary.split(/\n\n?Note:/i).first&.strip
      
      if summary.match?(/^\d+\.\s/)
        Rails.logger.warn "AI returned numbered list - converting to paragraph"
        summary = summary.gsub(/^\d+\.\s+/, '').gsub(/\n+/, ' ')
      end
      
      summary.strip
    else
      summary
    end
  end
end
