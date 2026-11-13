// Deben coincidir con Arroyo::Setting (app/models/arroyo/setting.rb)
export const POST_SALE_STAGES = ['d1', 'd7', 'd30'];
export const MAX_FOOTER_LENGTH = 5000;
export const MAX_WINDOW_NUDGE_LENGTH = 1000;
// Variables que Arroyo::Commercial::WindowNudgeService reemplaza en el aviso de ventana
export const NUDGE_VARIABLES = [
  '{{contact.first_name}}',
  '{{contact.name}}',
  '{{agent.first_name}}',
];
