# Constraint Overhaul
Total rewrite of constraints for Garrysmod featuring a multitude of bugfixes and optimizations.


Spawn times and spawn lag for contraptions are heavily reduced. Creating and destroying constraints has far less a toll on the server.
 
Contraptions are more logical in the creation of constraint systems which results in less entities being created (Less lag!) and the contraption being much sturdier.
 
Optimizations to the constraint library reduces the load of its use in other addons and even native scripts (such as gravity gun unfreeze, remover, etc), resulting in a great decrease in server strain. For example, constraint.GetAllConstrainedEntities is 24 times faster.
