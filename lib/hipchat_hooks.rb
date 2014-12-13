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

    build_message(project, text)
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

    build_message(project, text)
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

    build_message(project, text)
  end

  private

  def hipchat_configured?(project)
    token_configured = !project.hipchat_auth_token.empty? or !Setting.plugin_redmine_hipchat[:auth_token].empty?

    if project.hipchat_room_name.length > 0 and token_configured
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

  def hipchat_from(project)
    if !project.hipchat_from.empty?
      project.hipchat_from
    elsif !Setting.plugin_redmine_hipchat[:from].empty?
      Setting.plugin_redmine_hipchat[:from]
    else
      'Redmine'
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

  def build_message(project, text)
    send_request({
      auth_token: hipchat_auth_token(project),
      room_id: hipchat_room_name(project),
      notify: hipchat_notify(project) ? 1 : 0,
      from: hipchat_from(project),
      message: text
    })
  end

  def send_request(data)
    Rails.logger.info "Hipchat: sending message: #{ data.inspect }"

    req = Net::HTTP::Post.new("/v1/rooms/message")
    req.set_form_data(data)
    req["Content-Type"] = 'application/x-www-form-urlencoded'

    endpoint = if Setting.plugin_redmine_hipchat[:endpoint].empty?
      'api.hipchat.com'
    else
      Setting.plugin_redmine_hipchat[:endpoint]
    end

    http = Net::HTTP.new(endpoint, 443)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_PEER

    begin
      http.start do |connection|
        response = connection.request(req)

        Rails.logger.info "Hipchat: #{ response.code } response with '#{ response.msg }' message." unless response.code == '200'
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
