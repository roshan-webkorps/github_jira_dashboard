class Pioneer::JiraSyncService < BaseJiraSyncService
  protected

  def get_jira_service
    Pioneer::JiraService.new
  end

  def get_project_keys
    [ "AP2", "ESI2", "PP", "INT2", "MOB2" ]
  end

  def get_app_type
    "pioneer"
  end

  def is_known_developer?(name, email, account_id)
    get_known_developer_account_ids.include?(account_id)
  end

  def get_known_developer_account_ids
    [
      "712020:bb1ad205-1807-4077-a333-bfdd6f046c87", # Aayush Kumar Shukla
      "5fc9548aaca10c0069d8e646", # Vikas
      "629e227a4e1a640070c27177", # Harsh
      "5f5f73becacd8300775466c4", # Priya Thakur
      "712020:6232c287-6cf4-4546-bf3e-bf9d0c425e13", # Gautam Patil
      "712020:ced2bd21-fa33-4272-8747-98ef04c397aa", # Jamila Batterywala
      "712020:4db70c5c-7aff-4259-b545-d6b41b8e675f", # Akshay Khajuriya
      "712020:1b37cc3e-482d-4403-bca8-41fd7f532cdc", # Mrunal Selokar
      "5ffbb4184d2179006ee755fe", # Swapnil Bhosale
      "712020:43ee04f9-e3fc-4914-b4f4-3c095e2a4ddb", # Nikesh Kumar
      "60d5fd3a9469280070340fcb", # Krishna Sahoo
      "5f46ee1b347294003e7435bd", # mehul
      "631eda46cf721d09b015b8ed", # Gaurav Patil
      "712020:64eb99e1-a6e1-43de-b960-04ed0ef79148", # sagar pithiya
      "63216307f8c7bc1f35837f67", # rohitmahajan
      "712020:e9bc05ff-a361-4448-b1fe-a21f89ee3588", # Abhishek Patidar
      "712020:a543b715-8d66-4d7c-823d-4d44f2aee9a8", # Aniket Shinde
      "712020:edf1b4ef-8ed0-4c65-86ff-745c78999dcb", # Mohit Jangid 
      "5f46ed831ac29c004525b36f", # Parakh Garg
      "712020:edd73c8b-3c5d-43e2-be1a-5ba67514f80a" # Vishal Paliwal
    ]
  end
end
