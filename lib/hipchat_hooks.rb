class NotificationHook < Redmine::Hook::Listener

  def controller_issues_new_after_save(context = {})
    issue   = context[:issue]
    project = issue.project
    return true unless hipchat_configured?(project)

    author  = CGI::escapeHTML(User.current.name)
    tracker = CGI::escapeHTML(issue.tracker.name.downcase)
    subject = CGI::escapeHTML(issue.subject)
    url     = get_url(issue)
    text    = "#{author} reported #{project.name} #{tracker} <a href=\"#{url}\">##{issue.id}</a>: #{subject}"

    data          = {}
    data[:text]   = text
    data[:token]  = hipchat_auth_token(project)
    data[:room]   = hipchat_room_name(project)
    data[:notify] = hipchat_notify(project)

    send_message(data)
  end

  def controller_issues_edit_after_save(context = {})
    issue   = context[:issue]
    project = issue.project
    return true unless hipchat_configured?(project)

    author  = CGI::escapeHTML(User.current.name)
    tracker = CGI::escapeHTML(issue.tracker.name.downcase)
    subject = CGI::escapeHTML(issue.subject)
    comment = CGI::escapeHTML(context[:journal].notes)
    url     = get_url(issue)
    text    = "#{author} updated #{project.name} #{tracker} <a href=\"#{url}\">##{issue.id}</a>: #{subject}"
    text   += ": <i>#{truncate(comment)}</i>" unless comment.blank?

    data          = {}
    data[:text]   = text
    data[:token]  = hipchat_auth_token(project)
    data[:room]   = hipchat_room_name(project)
    data[:notify] = hipchat_notify(project)

    send_message(data)
  end

  def controller_wiki_edit_after_save(context = {})
    page    = context[:page]
    project = page.wiki.project
    return true unless hipchat_configured?(project)

    author       = CGI::escapeHTML(User.current.name)
    wiki         = CGI::escapeHTML(page.pretty_title)
    project_name = CGI::escapeHTML(project.name)
    url          = get_url(page)
    text         = "#{author} edited #{project_name} wiki page <a href=\"#{url}\">#{wiki}</a>"

    data          = {}
    data[:text]   = text
    data[:token]  = hipchat_auth_token(project)
    data[:room]   = hipchat_room_name(project)
    data[:notify] = hipchat_notify(project)

    send_message(data)
  end

  private

  def hipchat_configured?(project)
    if project.hipchat_room_name.length > 0
      true
    elsif Setting.plugin_redmine_hipchat[:projects] and
          Setting.plugin_redmine_hipchat[:projects].include?(project.id.to_s) and
          Setting.plugin_redmine_hipchat[:auth_token] and
          Setting.plugin_redmine_hipchat[:room_id]
      true
    else
      Rails.logger.info "Hipchat: Not sending message, missing config."
      false
    end
  end

  def hipchat_auth_token(project)
    if project.hipchat_auth_token.empty?
      Setting.plugin_redmine_hipchat[:auth_token]
    else
      project.hipchat_auth_token
    end
  end

  def hipchat_room_name(project)
    if project.hipchat_room_name.empty?
      Setting.plugin_redmine_hipchat[:room_id]
    else
      project.hipchat_room_name
    end
  end

  def hipchat_notify(project)
    if project.hipchat_room_name.empty?
      Setting.plugin_redmine_hipchat[:notify]
    else
      project.hipchat_notify
    end
  end

  def get_url(object)
    case object
      when Issue    then "#{Setting[:protocol]}://#{Setting[:host_name]}/issues/#{object.id}"
      when WikiPage then "#{Setting[:protocol]}://#{Setting[:host_name]}/projects/#{object.wiki.project.identifier}/wiki/#{object.title}"
    else
      Rails.logger.error "Hipchat: Asked for the url of an unsupported object #{object.inspect}"
    end
  end

  def send_message(data)
    Rails.logger.info "Hipchat: sending message to #{ data[:room] } room."

    req = Net::HTTP::Post.new("/v1/rooms/message")
    req.set_form_data({
      :auth_token => data[:token],
      :room_id => data[:room],
      :notify => data[:notify] ? 1 : 0,
      :from => 'Redmine',
      :message => data[:text]
    })
    req["Content-Type"] = 'application/x-www-form-urlencoded'

    http = Net::HTTP.new("api.hipchat.com", 443)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_PEER

    begin
      http.start do |connection|
        response = connection.request(req)

        Rails.logger.info "Hipchat: response #{response.code}" unless response.code == '200'
      end
    rescue Net::HTTPBadResponse => e
      Rails.logger.error "Hipchat: Error hitting API: #{e}"
    end
  end

  def truncate(text, length = 20, end_string = '…')
    return unless text
    words = text.split()
    words[0..(length-1)].join(' ') + (words.length > length ? end_string : '')
  end
end
