class TranscriptSearchService
  
  def self.search(query_text, limit: 5, source: 'otter', date_from: nil)
    return [] if query_text.blank?
    
    begin
      # Generate embedding for the query
      query_embedding = generate_embedding(query_text)
      return [] if query_embedding.nil?
      
      # Perform vector search
      search_with_embedding(query_embedding, limit: limit, source: source, date_from: date_from)
    rescue => e
      Rails.logger.error "Transcript search error: #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")
      []
    end
  end
  
  private
  
  # Generate embedding using AWS Bedrock Titan
  def self.generate_embedding(text)
    client = initialize_bedrock_client
    
    request_body = {
      inputText: text.strip
    }
    
    response = client.invoke_model({
      model_id: "amazon.titan-embed-text-v2:0",
      body: request_body.to_json,
      content_type: "application/json"
    })
    
    response_body = JSON.parse(response.body.read)
    response_body["embedding"]  # Returns array of 1024 floats
  rescue => e
    Rails.logger.error "Embedding generation error: #{e.message}"
    nil
  end
  
  # Search using vector similarity
  def self.search_with_embedding(embedding_array, limit: 5, source: nil, date_from: nil)
    embedding_str = "[#{embedding_array.join(',')}]"
    
    sql = <<-SQL
      SELECT 
        doc_uid,
        chunk_idx,
        source,
        title,
        text,
        author,
        meeting_date,
        created_at_utc,
        embedding <=> '#{embedding_str}'::vector AS distance
      FROM doc_chunks
      WHERE 1=1
    SQL
    
    if source.present?
      sql += " AND source = '#{source}'"
    end
    
    # Filter by meeting date (not created_at_utc)
    if date_from.present?
      sql += " AND meeting_date >= '#{date_from.to_date}'"
    end
    
    sql += " ORDER BY embedding <=> '#{embedding_str}'::vector"
    sql += " LIMIT #{limit}"
    
    results = ActiveRecord::Base.connection.exec_query(sql)
    results.to_a
  end
  
  def self.initialize_bedrock_client
    require "aws-sdk-bedrockruntime"
    
    Aws::BedrockRuntime::Client.new(
      region: ENV["AWS_REGION"] || "us-east-1",
      credentials: Aws::Credentials.new(
        ENV["AWS_ACCESS_KEY_ID"],
        ENV["AWS_SECRET_ACCESS_KEY"]
      )
    )
  end
end
