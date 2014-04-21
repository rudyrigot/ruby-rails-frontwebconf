module PrismicHelper

  # For a given document, describes its URL on your front-office.
  # You really should edit this method, so that it supports all the document types your users might link to.
  #
  # Beware: doc is not a Prismic::Document, but a Prismic::Fragments::DocumentLink,
  # containing only the information you already have without querying more (see DocumentLink documentation)
  def link_resolver(maybe_ref)
    @link_resolver ||= Prismic::LinkResolver.new(maybe_ref){|doc|
      return '#' if doc.broken?
      case doc.link_type
      when "homepage"
        root_path(ref: maybe_ref)
      when "article" # This type is special: the URL is built depending on the document's prismic.io bookmark
        case doc.id
        when api.bookmark("about")
          about_path(ref: maybe_ref)
        when api.bookmark("schedule")
          schedule_path(ref: maybe_ref)
        when api.bookmark("speakers")
          speakers_path(ref: maybe_ref)
        when api.bookmark("venues")
          venues_path(ref: maybe_ref)
        else
          article_path(id: doc.id, slug: doc.slug, ref: maybe_ref)
        end
      when "blog"
        newspost_path(id: doc.id, slug: doc.slug, ref: maybe_ref)
      when "footerlinks"
        root_path(ref: maybe_ref) + "\#footer"
      when "session"
        talk_path(id: doc.id, slug: doc.slug, ref: maybe_ref)
      when "speaker"
        speakers_path(ref: maybe_ref) + "\#" + doc.id
      when "sponsor"
        root_path(ref: maybe_ref) + "\#sponsorstitle"
      when "venue"
        venues_path(ref: maybe_ref) + "\#" + doc.id
      else
        raise "link_resolver doesn't know how to write URLs for #{doc.link_type} type."
      end

      # maybe_ref is not expected by document path, so it appends a ?ref=maybe_ref to the URL;
      # since maybe_ref is nil when on master ref, it appends nothing.
      # You should do the same for every path method used here in the link_resolver and elsewhere in your app,
      # so links propagate the ref id when you're previewing future content releases.
    }
  end

  # Checks if the user is connected to prismic.io's OAuth2.
  def connected?
    !!@access_token
  end

  # Checks if the user is connected or the app has an access token set for all users.
  def privileged_access?
    connected? || PrismicService.access_token
  end

  # Return the actual used reference
  def ref
    @ref ||= maybe_ref || api.master_ref.ref
  end

  # Return the set reference
  def maybe_ref
    @maybe_ref ||= (params[:ref].blank? ? nil : params[:ref])
  end

  # Allows to call api directly in the view
  # (to check the bookmarks, for instance, you shouldn't query in the view!)
  def api
    @api
  end

end
