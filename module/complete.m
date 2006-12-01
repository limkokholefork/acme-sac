Complete: module
{
	PATH:	con "/dis/lib/complete.dis";

	Completion: adt {
		advance: 	int;
		complete:	int;
		str:		string;
		nmatch:	int;
		nfile:		int;
		filename : array of string;
	};

	init:fn();
	complete: fn(dir, s: string): ref Completion;
};
