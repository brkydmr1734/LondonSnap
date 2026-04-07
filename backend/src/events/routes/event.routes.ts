import { Router } from 'express';
import { eventController } from '../controllers/event.controller';
import { universityStudentMiddleware } from '../../auth/middleware/auth.middleware';

const router = Router();

// Public events
router.get('/', eventController.getEvents);
router.get('/:eventId', eventController.getEventById);

// Create event
router.post('/', eventController.createEvent);

// Update event
router.put('/:eventId', eventController.updateEvent);

// Delete event
router.delete('/:eventId', eventController.deleteEvent);

// RSVP
router.post('/:eventId/rsvp', eventController.rsvpEvent);
router.delete('/:eventId/rsvp', eventController.cancelRsvp);

// Get attendees
router.get('/:eventId/attendees', eventController.getAttendees);

// University events
router.get('/university/:universityId', eventController.getUniversityEvents);

// Nearby events
router.get('/area/:area', eventController.getEventsByArea);

export default router;
