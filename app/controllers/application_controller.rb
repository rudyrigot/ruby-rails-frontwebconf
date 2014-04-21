class ApplicationController < ActionController::Base
  protect_from_forgery with: :exception

  # Rescue OAuth errors for some actions
  rescue_from Prismic::API::PrismicWSAuthError, with: :redirect_to_signin,
                                                 only: [:index, :download, :dochome, :doc, :docsearch, :getinvolved]

  before_action :set_footer

  # Homepage action: querying the "everything" form (all the documents, paginated by 20)
  def index
  	# Retrieving the useful documents from prismic.io
  	@document = PrismicService.get_document(api.bookmark("homepage"), api, ref) # the homepage document
  	@sponsorlink = PrismicService.get_document(api.bookmark("sponsorlink"), api, ref) # the sponsor link (for the sponsor call-to-action)
  	@speakerlink = PrismicService.get_document(api.bookmark("speakerlink"), api, ref) # the speaker link (for the speaker call-to-action)
  	@speakers = api.form("speakers").query('[[:d = at(document.tags, ["featured"])]]').submit(ref).to_a.shuffle.first(4) ## all featured speakers, shuffled and limited
  	@silver_sponsors = api.form('sponsors').query('[[:d = at(my.sponsor.level, "silver")]]').submit(ref) # retrieving all the silver sponsors
  	@bronze_sponsors = api.form('sponsors').query('[[:d = at(my.sponsor.level, "bronze")]]').submit(ref) # retrieving all the bronze sponsors
  	# No need to retrieve the gold sponsors: they're already retrieved in set_footer
  end

  def about
  	@document = PrismicService.get_document(api.bookmark("about"), api, ref)
  end

  def article
    id = params[:id]
    slug = params[:slug]

    @document = PrismicService.get_document(id, api, ref)

    # Checking if the doc / slug combination is right, and doing what needs to be done
    @slug_checker = PrismicService.slug_checker(@document, slug)
    if !@slug_checker[:correct]
      render status: :not_found, file: "#{Rails.root}/public/404", layout: false if !@slug_checker[:redirect]
      redirect_to blogpost_path(id, @document.slug), status: :moved_permanently if @slug_checker[:redirect]
    end
  end

  # This is the most complex controller action by far, because the page represents a large diversity of
  # documents, that need querying first (sessions, venues, speakers, ...), but them mostly that need to
  # be organized with each other.
  # The goal is to build a Hash with conference days as keys, and an ordered array of the sessions
  # For the sessions, we'll store them as Hashes, containing:
  #   * the datetimes of beginning and end,
  #   * the speaker,
  #   * document(s),
  #   * the venue document,
  #   * and the session document itself.
  # An extra complexity here is due to the datetime fragments not being implemented in prismic.io yet (we're
  # rebuilding DateTimes from separate Number fragments)
  def schedule
  	@document = PrismicService.get_document(api.bookmark("schedule"), api, ref)

    # Retrieving venues
    @venues_by_id = api.form("venues").submit(ref).group_by{|venue| venue.id}

    # Retrieving speakers
    @speakers_by_id = api.form("speakers").submit(ref).group_by{|speaker| speaker.id}


  	@sessions = api.form("sessions").submit(ref)

  	@sorted_sessions_by_day = @sessions.select { |session| # Getting rid of incompletely authored sessions
			session['session.date_beginning'] && session['session.hour_beginning'] && session['session.hour_end']
		}.map { |session|
			# Getting the date, and creating an empty array if date wasn't known yet
			date = session['session.date_beginning'].value.to_date

			# Building the Hash representing a session, and returning it as the element to map
			hour_beginning = session['session.hour_beginning'].value + (session['session.am_pm_beginning'].value == 'pm' ? 12 : 0 )
			minutes_beginning = session['session.minutes_beginning'] ? session['session.minutes_beginning'].value : 0
			hour_end = session['session.hour_end'].value + (session['session.am_pm_end'].value == 'pm' ? 12 : 0 )
			minutes_end = session['session.minutes_end'] ? session['session.minutes_end'].value : 0
			{
				:beginning => DateTime.new(date.year, date.month, date.day, hour_beginning, minutes_beginning, 0, '-8'),
				:end => DateTime.new(date.year, date.month, date.day, hour_end, minutes_end, 0, '-8'),
				:document => session,
        :speakers => (session['session.speakers'] ? session['session.speakers'].select{ |group|
          group['speaker']
        }.map{ |group|
          @speakers_by_id[group['speaker'].id][0]
        } : nil), # an array of the speakers, or nil
        :venue => @venues_by_id[session['session.venue'].id][0] # the venue
			}
  	}.group_by { |session_hash| session_hash[:document]['session.date_beginning'].value.to_date } # group by day

  	# All the structure is there, but within each day, the sessions aren't sorted; let's sort them!
  	@sorted_sessions_by_day.each {|_, session_array|
  		session_array.sort!{|session1, session2| session1[:beginning] > session2[:beginning] ? 1 : -1}
  	}

  end

  def speakers
  	@document = PrismicService.get_document(api.bookmark("speakers"), api, ref)

    @speakers_hash = api.form("speakers").submit(ref).map{ |speaker|
      {
        :speaker => speaker,
        :sessions => api.form("sessions").query("[[:d = at(my.session.speakers.speaker, \"#{speaker.id}\")]]").submit(ref)
      }
    }
  end

  def venues
  	@document = PrismicService.get_document(api.bookmark("venues"), api, ref)

    @venues = api.form("venues").submit(ref)
  end

  def talk
    id = params[:id]
    slug = params[:slug]

    @document = PrismicService.get_document(id, api, ref)

    # Checking if the doc / slug combination is right, and doing what needs to be done
    @slug_checker = PrismicService.slug_checker(@document, slug)
    if !@slug_checker[:correct]
      render status: :not_found, file: "#{Rails.root}/public/404", layout: false if !@slug_checker[:redirect]
      redirect_to blogpost_path(id, @document.slug), status: :moved_permanently if @slug_checker[:redirect]
    else
      @speakers = @document['session.speakers'] ? @document['session.speakers'].select{|speaker| speaker['speaker'] }.map {|speaker| PrismicService.get_document(speaker['speaker'].id, api, @ref) } : nil
      @venue = @document['session.venue'] ? PrismicService.get_document(@document['session.venue'].id, api, @ref) : nil
    end
  end

  def newshome
    @documents = api.form("blog").orderings("[my.blog.date desc]").submit(ref)
    render :newslist
  end

  def newssearch
    @documents = api.form("blog").query(%([[:d = fulltext(document, "#{params[:q]}")]])).orderings("[my.blog.date desc]").submit(ref)
    render :newslist
  end

  def newspost
    id = params[:id]
    slug = params[:slug]

    @document = PrismicService.get_document(id, api, ref)

    # This is how an URL gets checked (with a clean redirect if the slug is one that used to be right, but has changed)
    # Of course, you can change slug_checker in prismic_service.rb, depending on your URL strategy.
    @slug_checker = PrismicService.slug_checker(@document, slug)
    if !@slug_checker[:correct]
      render inline: "Document not found", status: :not_found if !@slug_checker[:redirect]
      redirect_to document_path(id, @document.slug), status: :moved_permanently if @slug_checker[:redirect]
    end
  end

  # Single-document page action: mostly, setting the @document instance variable, and checking the URL
  def document
    id = params[:id]
    slug = params[:slug]

    @document = PrismicService.get_document(id, api, ref)

    # This is how an URL gets checked (with a clean redirect if the slug is one that used to be right, but has changed)
    # Of course, you can change slug_checker in prismic_service.rb, depending on your URL strategy.
    @slug_checker = PrismicService.slug_checker(@document, slug)
    if !@slug_checker[:correct]
      render inline: "Document not found", status: :not_found if !@slug_checker[:redirect]
      redirect_to document_path(id, @document.slug), status: :moved_permanently if @slug_checker[:redirect]
    end
  end

  # Search result: querying all documents containing the q parameter
  def search
    @documents = api.form("everything")
                    .query(%([[:d = fulltext(document, "#{params[:q]}")]]))
                    .submit(ref)
  end


  private

  ## before_action method set_footer
  def set_footer
  	@gold_sponsors = api.form('sponsors').query('[[:d = at(my.sponsor.level, "gold")]]').submit(ref)
  	@footerlinks = api.form('footerlinks').orderings('[my.footerlinks.priority]').submit(ref)
  	@latest_news = api.form('blog').orderings('[my.blog.date desc]').submit(ref).first(5)
  end

  # Used to rescue issues PrismicWSErrors in controller actions
  def redirect_to_signin
    redirect_to signin_path
  end


  # Returning the actual ref id being queried, even if it's the master ref.
  # To be used to call the API, for instance: api.form('everything').submit(ref)
  def ref
    @ref ||= maybe_ref || api.master_ref.ref
  end

  # Returning the ref id being queried, or nil if it is the master ref.
  # To be used where you want nothing if on master, but something if on another release.
  # For instance:
  #  * you can use it to call Rails routes: document_path(ref: maybe_ref), which will add "?ref=refid" as a param, but only when needed.
  #  * you can pass it to your link_resolver method, which will use it accordingly.
  def maybe_ref
    @maybe_ref ||= (params[:ref].blank? ? nil : params[:ref])
  end

  ##

  # Easier access and initialization of the Prismic::API object.
  def api
    @api ||= PrismicService.init_api(access_token)
    rescue Prismic::API::PrismicWSAuthError => e
      reset_access_token!
    raise e
  end

  def access_token
    @access_token = session['ACCESS_TOKEN']
  end

  def reset_access_token!
    @access_token = session['ACCESS_TOKEN'] = nil
  end

end
