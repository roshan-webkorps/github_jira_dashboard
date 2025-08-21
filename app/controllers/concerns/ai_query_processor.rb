# app/controllers/concerns/ai_query_processor.rb
module AiQueryProcessor
  extend ActiveSupport::Concern
  
  def process_ai_query(user_query)
    begin
      # Get AI response
      ai_response = call_openai_api(user_query)
      
      # Parse the AI response
      parsed_response = JSON.parse(ai_response)
      
      # Validate and execute the SQL
      if parsed_response['sql'].present?
        results = execute_safe_query(parsed_response['sql'])
        
        # Format results for frontend
        format_query_results(results, parsed_response)
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
    require 'net/http'
    require 'json'
    
    uri = URI('https://api.openai.com/v1/chat/completions')
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    
    request = Net::HTTP::Post.new(uri)
    request['Authorization'] = "Bearer #{ENV['OPENAI_API_KEY']}"
    request['Content-Type'] = 'application/json'
    
    # Build the prompt with schema context
    system_prompt = build_system_prompt
    
    request.body = {
      model: "gpt-3.5-turbo",
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
      max_tokens: 500,
      temperature: 0.1
    }.to_json
    
    response = http.request(request)
    
    if response.code == '200'
      result = JSON.parse(response.body)
      result.dig('choices', 0, 'message', 'content')
    else
      raise "OpenAI API Error: #{response.code}"
    end
  end
  
  def build_system_prompt
    <<~PROMPT
      You are a SQL query generator for a GitHub and Jira analytics dashboard. 
      
      Database Schema:
      - developers: id, name, github_username, jira_username, email
      - repositories: id, name, full_name, owner, language  
      - commits: id, sha, message, developer_id, repository_id, committed_at, additions, deletions
      - pull_requests: id, number, title, state, developer_id, repository_id, opened_at, closed_at, merged_at
      - tickets: id, key, title, status, priority, developer_id, created_at_jira, updated_at_jira
      
      Rules:
      1. ONLY generate SELECT queries - no INSERT, UPDATE, DELETE, DROP
      2. Always JOIN with developers table to get names, not just IDs
      3. Use proper time filtering with DATE functions when needed
      4. Limit results to reasonable numbers (TOP 10, etc.)
      5. Return response as JSON: {"sql": "SELECT...", "description": "Human readable description", "chart_type": "bar|pie|table"}
      
      Common patterns:
      - Top developers by commits: JOIN developers, COUNT commits, GROUP BY developer
      - Time-based queries: Use committed_at, opened_at, created_at_jira
      - PR analysis: Use state='open'/'closed', merged_at IS NOT NULL
      - Repository stats: JOIN repositories, GROUP BY repo name
      
      If you cannot generate a safe query, return: {"error": "Cannot process this query"}
    PROMPT
  end
  
  def execute_safe_query(sql)
    # Basic SQL injection protection - only allow SELECT
    unless sql.strip.downcase.start_with?('select')
      raise "Only SELECT queries are allowed"
    end
    
    # Prevent dangerous keywords
    dangerous_keywords = ['drop', 'delete', 'update', 'insert', 'alter', 'create', 'truncate']
    if dangerous_keywords.any? { |keyword| sql.downcase.include?(keyword) }
      raise "Query contains prohibited keywords"
    end
    
    # Execute query with timeout
    ActiveRecord::Base.connection.execute("SET statement_timeout = 10000") # 10 seconds
    result = ActiveRecord::Base.connection.exec_query(sql)
    
    # Convert to array of hashes for easier processing
    result.to_a
  end
  
  def format_query_results(results, ai_response)
    return { error: "No results found" } if results.empty?
    
    chart_type = ai_response['chart_type'] || 'table'
    description = ai_response['description'] || 'Query Results'
    
    # Format based on chart type and result structure
    formatted_data = case chart_type
    when 'bar'
      format_for_bar_chart(results)
    when 'pie'  
      format_for_pie_chart(results)
    else
      format_for_table(results)
    end
    
    {
      success: true,
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
        datasets: [{
          label: columns[1].humanize,
          data: values,
          backgroundColor: 'rgba(52, 152, 219, 0.6)',
          borderColor: 'rgba(52, 152, 219, 1)',
          borderWidth: 1
        }]
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
        'rgba(52, 152, 219, 0.6)',   # Blue
        'rgba(46, 204, 113, 0.6)',   # Green  
        'rgba(241, 196, 15, 0.6)',   # Yellow
        'rgba(231, 76, 60, 0.6)',    # Red
        'rgba(155, 89, 182, 0.6)',   # Purple
        'rgba(230, 126, 34, 0.6)',   # Orange
      ]
      
      {
        labels: labels,
        datasets: [{
          data: data,
          backgroundColor: colors.cycle.take(data.length),
          borderColor: colors.cycle.take(data.length).map { |c| c.gsub('0.6', '1') },
          borderWidth: 1
        }]
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
