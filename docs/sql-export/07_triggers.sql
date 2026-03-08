DROP TRIGGER IF EXISTS check_session_closed ON public.interval_presence;
CREATE TRIGGER check_session_closed BEFORE INSERT OR DELETE OR UPDATE ON interval_presence FOR EACH ROW EXECUTE FUNCTION prevent_change_on_locked_session();

DROP TRIGGER IF EXISTS update_members_modtime ON public.members;
CREATE TRIGGER update_members_modtime BEFORE UPDATE ON members FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS trigger_auto_complete_session ON public.session_costs_snapshot;
CREATE TRIGGER trigger_auto_complete_session AFTER UPDATE OF status ON session_costs_snapshot FOR EACH ROW EXECUTE FUNCTION check_session_completion();

DROP TRIGGER IF EXISTS on_booking_change ON public.session_court_bookings;
CREATE TRIGGER on_booking_change AFTER INSERT OR DELETE OR UPDATE ON session_court_bookings FOR EACH ROW EXECUTE FUNCTION trigger_refresh_courts();

DROP TRIGGER IF EXISTS check_session_closed ON public.session_registrations;
CREATE TRIGGER check_session_closed BEFORE INSERT OR DELETE OR UPDATE ON session_registrations FOR EACH ROW EXECUTE FUNCTION prevent_change_on_locked_session();

DROP TRIGGER IF EXISTS update_sessions_modtime ON public.sessions;
CREATE TRIGGER update_sessions_modtime BEFORE UPDATE ON sessions FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
