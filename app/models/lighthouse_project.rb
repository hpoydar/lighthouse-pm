# Wraps some of the API functionality so that
# we don't have sorting code and similar behavior 
# living in views
class LighthouseProject
  
  require 'enumerator'
  
  def initialize( api_access_options = {} ) 
    @api_access_options = api_access_options
    authenticate_and_retrieve_project
    gather_tickets_and_milestones
  end 
  
  class TicketStruct < Struct.new( :title, :state, :estimated, :actual, :assigned_to, :milestone_index, :untimed ); end
  class MilestoneStruct < Struct.new( :index, :title ); end
  
  
  %w( name open_tickets_count ).each do |api_method|
    define_method(api_method) { @project.send("#{api_method}") }
  end
  
  def sorted_milestones
    @project_milestones
  end
  alias_method :milestones,  :sorted_milestones
  
  
  def tickets_by_milestone( milestone )
    @project_tickets.reject { |t| t.milestone_index != milestone.index }
  end
  
  def time_totals_by_milestone( milestone )
    sum_estimated_and_actual_times( tickets_by_milestone( milestone ) )
  end
  
  def time_totals
    sum_estimated_and_actual_times( @project_tickets )
  end


  def gather_tickets_and_milestones
    @project_tickets = []
    @project_milestones = @project.milestones.sort_by { |m| m.due_on || Time.now + 5.years }.to_enum(:each_with_index).map { |m,i| MilestoneStruct.new( i, m.title ) }
    @project_milestones.each do |m| 
      @project.tickets( :q => "milestone:\"#{m.title}\"").sort_by { |t| [ t.state, t.title ] }.each do |t|
        @project_tickets << TicketStruct.new( 
           t.title,
           t.state,
           LighthouseProject.parse_estimated_time( t.title ),
           LighthouseProject.parse_actual_time( t.title ),
           t.assigned_user_id,
           m.index,
           ( LighthouseProject.parse_estimated_time( t.title ) == 0.0 && LighthouseProject.parse_actual_time( t.title ) == 0.0 ) 
         ) 
      end
    end
    Merb.logger.info( @project_tickets.inspect  )
  end


  def authenticate_and_retrieve_project
    begin
      Lighthouse.account = @api_access_options[:account_name] || ''
      Lighthouse.token = @api_access_options[:api_token] || ''
      @project = Lighthouse::Project.find(  ( @api_access_options[:project_id] || '' ).to_i )
    rescue
      raise "Project details could not be retrieved from Lighthouse using the supplied credentials"
    end
    gather_tickets_and_milestones
  end
  
  def sum_estimated_and_actual_times( ticket_collection )
    
      open_estimated = closed_estimated = closed_actual = 0.0
      
      ticket_collection.each do |t|
        unless t.state == 'resolved'
          open_estimated += t.estimated
        else
          closed_estimated += t.estimated
          closed_actual += t.actual
        end
      end

      { 
        :open => { :estimated  => open_estimated },
        :closed => { :estimated  => closed_estimated, :actual => closed_actual }  
      }
  
  end
  

  def self.parse_estimated_time( title )
    ( title.match(/EST:(.*?)d/) || [0,0] )[1].to_s.to_f
  end
  
  def self.parse_actual_time( title )
    ( title.match(/ACT:(.*?)d/) || [0,0] )[1].to_s.to_f
  end

end