from abc import ABC, abstractmethod

class Event(ABC):

  @abstractmethod
  def has_event_happened(): 
    pass
